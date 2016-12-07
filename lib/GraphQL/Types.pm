use Hash::Ordered;

unit module GraphQL::Types;

class GraphQL::Type
{
    has Str  $.name;
    has Str  $.description is rw;
}

class GraphQL::Scalar is GraphQL::Type
{
    has Str $.kind = 'SCALAR';

    method Str { "scalar $.name\n" }
}

class GraphQL::String is GraphQL::Scalar
{
    has Str $.name = 'String';
}

class GraphQL::Int is GraphQL::Scalar
{
    has Str $.name = 'Int';
}

class GraphQL::Float is GraphQL::Scalar
{
    has Str $.name = 'Float';
}

class GraphQL::Boolean is GraphQL::Scalar
{
    has Str $.name = 'Boolean';
}

class GraphQL::ID is GraphQL::Scalar
{
    has Str $.name = 'ID';
}

class GraphQL::List is GraphQL::Type
{
    has Str $.kind = 'LIST';
    has GraphQL::Type $.ofType is rw;
    
    method name { '[' ~ $.ofType.name ~ ']' }
}

class GraphQL::Non-Null is GraphQL::Type
{
    has Str $.kind = 'NON_NULL';
    has GraphQL::Type $.ofType is rw;

    method name { $!ofType.name ~ '!' }
    method Str  { $!ofType.Str  ~ '!' }
}

# Because the GraphQL spec stupidly defines these to be ordered..
class GraphQL::FieldList is Hash::Ordered {}

class GraphQL::Interface is GraphQL::Type
{
    has Str $.kind = 'INTERFACE';
    has GraphQL::FieldList $.fields;
    has GraphQL::Type @.possibleTypes;

    method fields(Bool :$includeDeprecated)
    {
	$!fields.values.grep: {.name !~~ /^__/ and
				   ($includeDeprecated or not .isDeprecated) }
    }

    method Str
    {
        "interface $.name \{\n" ~
            $!fields.values.map({"  " ~ .Str}).join("\n") ~
        "\n}\n"
    }
}

class GraphQL::Object is GraphQL::Type
{
    has Str $.kind = 'OBJECT';
    has GraphQL::FieldList $.fields;
    has GraphQL::Interface @.interfaces is rw;

    method addfield($field) { $!fields{$field.name} = $field; }

    method field($fieldname) { $!fields{$fieldname} }

    method fields(Bool $includeDeprecated)
    {
	$!fields.values.grep: {.name !~~ /^__/ and
				   ($includeDeprecated or not .isDeprecated) }
    }
    
    method fragment-applies($fragmentType)
    {
        return True if $fragmentType eq $.name;
        die "Check FragmentType in interfaces";
    }

    method Str
    {
        "type $.name " ~ 
            ('implements ' ~ (@!interfaces».name).join(', ') ~ ' '
                if @.interfaces)
        ~ "\{\n" ~
        $.fields(True).values.grep({.name !~~ /^__/})
                             .map({'  ' ~ .Str})
                             .join("\n")
	~ "\n}\n"
    }
}

class GraphQL::InputValue is GraphQL::Type
{
    has GraphQL::Type $.type is rw;
    has $.defaultValue;

    method Str
    {
        "$.name: $.type.name()" ~ (" = $.defaultValue"
                                       if $.defaultValue.defined)
    }
}

role Deprecatable
{
    has Bool $.isDeprecated = False;
    has Str $.deprecationReason;

    method deprecate(Str $reason = "No longer supported.")
    {
	$!isDeprecated = True;
	$!deprecationReason = $reason;
    }

    method deprecate-str
    {
	' @deprecated(reason: "' ~ $!deprecationReason ~ '")'
	    if $!isDeprecated;
    }
}

class GraphQL::Field is GraphQL::Type does Deprecatable
{
    has GraphQL::Type $.type is rw;
    has GraphQL::InputValue @.args is rw;
    has Sub $.resolver is rw;

    method Str
    {
        "$.name" ~
            ('(' ~ @!args.join(', ') ~ ')' if @!args)
        ~ ": $!type.name()" ~ self.deprecate-str
    }

    method resolve(:$objectValue, :%argumentValues)
    {
        unless $!resolver.defined
	{
	    return $objectValue."$.name"() if $objectValue.^can($.name);

	    die "No resolver for $objectValue.name(), $.name()";
	}

        #
        # To provide a lot of flexibility in how the resolver
        # gets called, introspect it and try to give it the args
        # it wants.  Just a few styles implemented so far.
        #
        my %args;

        given $!resolver
        {
            when Code
            {
                for $!resolver.signature.params -> $p
                {
                    if $p.named
                    {
                        for $p.named_names -> $param_name
                        {
                            if $param_name eq 'objectValue'
                            {
                                %args<objectValue> = $objectValue;
                                last;
                            }
                            if %argumentValues{$param_name}:exists
                            {
                                %args{$param_name} =
                                    %argumentValues{$param_name};
                                last;
                            }
                        }
                    }
                }
            }
        }

        return $!resolver(|%args);
    }
}

class GraphQL::Union is GraphQL::Type
{
    has $.kind = 'UNION';
    has GraphQL::Type @.possibleTypes;

    method Str
    {
        "union $.name = {(@!possibleTypes».name).join(' | ')}\n";
    }
}

class GraphQL::EnumValue is GraphQL::Scalar does Deprecatable
{
    
    method Str { $.name ~ self.deprecate-str }
}

class GraphQL::Enum is GraphQL::Scalar
{
    has Str $.kind = 'ENUM';
    has GraphQL::EnumValue @.enumValues;

    method enumValues(Bool :$includeDeprecated)
    {
	@!enumValues.grep: {$includeDeprecated or not .isDeprecated}
    }
    
    method Str
    {
        "enum $.name \{\n" ~
            @!enumValues.map({ "  $_.Str()"}).join("\n") ~
        "\n}\n";
    }
}

class GraphQL::Directive is GraphQL::Type
{
    has GraphQL::EnumValue @.locations;
    has GraphQL::InputValue @.args;
}

#
# Default Types
#
our $GraphQLString  is export = GraphQL::String.new;
our $GraphQLFloat   is export = GraphQL::Float.new;
our $GraphQLInt     is export = GraphQL::Int.new;
our $GraphQLBoolean is export = GraphQL::Boolean.new;
our $GraphQLID      is export = GraphQL::ID.new;

our %defaultTypes is export =
    Int     => $GraphQLInt,
    Float   => $GraphQLFloat,
    String  => $GraphQLString,
    Boolean => $GraphQLBoolean,
    ID      => $GraphQLID;

class GraphQL::Operation
{
    has Str $.operation = 'query';
    has Str $.name;
    has %.vars;
    has %.directives;
    has @.selectionset;  # QueryField or Fragment

    method Str
    {
        ("$.operation $.name " if $.name) ~ "\{\n" ~
            @.selectionset.map({.Str('  ')}).join('') ~
        "}\n"
    }
}

class GraphQL::QueryField
{
    has Str $.alias;
    has Str $.name;
    has %.args;
    has GraphQL::Directive @.directives;
    has @.selectionset;

    method responseKey { $!alias // $!name }

    method Str(Str $indent = '')
    {
        $indent ~ ($!alias ~ ':=' if $!alias) ~ $!name
        ~
            ( '(' ~ %!args.keys.map({$_.Str ~ ':' ~ %!args{$_}.perl})
                               .join(', ') ~ ')' if %!args)
        ~
            ( " \{\n" ~ @!selectionset.map({.Str($indent ~ '  ')}).join('') ~
              $indent ~ '}' if @!selectionset)
        ~ "\n"
    }
}

class GraphQL::Fragment
{
    has Str $.name;
    has Str $.onType;
    has @.directives;
    has @.selectionset;

    method Str($indent = '')
    {
        "fragment $.name on $.onType" ~
            ( " \{\n" ~ @!selectionset.map({.Str($indent ~ '  ')}).join('') ~
              $indent ~ '}' if @!selectionset)
    }
}

class GraphQL::FragmentSpread
{
    has Str $.name;
    has @.directives;

    method Str($indent = '')
    {
        "$indent... $.name\n"
    }
}

class GraphQL::InlineFragment
{
    has Str $.onType;
    has @.directives;
    has @.selectionset;

    method Str($indent = '')
    {
        "$indent..."
            ~ (" on $.onType" if $.onType)
            ~ " \{\n" ~ @!selectionset.map({.Str($indent ~ '  ')}).join('')
            ~ $indent ~ "}\n"
    }
}

class GraphQL::Document
{
    has GraphQL::Operation %.operations;
    has GraphQL::Fragment  %.fragments;

    method GetOperation($operationName)
    {
        if $operationName.defined
        {
            return %!operations{$operationName}
                if %!operations{$operationName}.defined;
            die "Must provide an operation."
        }

        return %!operations.values.first if %!operations.elems == 1;

        die "Must provide operation name if query contains multiple operations."
    }

    method Str
    {
        (%.operations.values.map({.Str}).join("\n"),
         %.fragments.values.map({.Str}).join("\n")).join("\n")
        ~ "\n";
    }
}

class GraphQL::Schema
{
    has %.types;
    has $.query is rw;
    has $.mutation is rw;

    method types { %!types.values }

    method addtype(GraphQL::Type $newtype)
    {
	%!types{$newtype.name} = $newtype
    }

    method type($typename) { %!types{$typename} }

    method queryType { %!types{$!query} }

    method mutationType { %!types{$!mutation} }

    method directives { die "No directives in schema yet" }

    method BUILD(:%types, :$!query = 'Query', :$!mutation)
    {
        %!types = %defaultTypes, %types;
    }

    method Str
    {
        my $str = '';

        for %!types.kv -> $typename, $type
        {
            next if %defaultTypes{$typename}.defined or $typename ~~ /^__/;
            $str ~= $type.Str ~ "\n";
        }

        $str ~= "schema \{\n";
	$str ~= "  query: $!query\n";
        $str ~= "  mutation: $!mutation\n" if $!mutation;
	$str ~= "}\n";
    }

    #
    # Two level Hash, first level is object type, second level is field name
    # pointing to something Callable
    method resolvers(%resolvers)
    {
        for %resolvers.kv -> $type, %obj
        {
            die "Undefined object $type" unless %!types{$type};

            for %obj.kv -> $field, $resolver
            {
                die "Undefined field $field for $type"
                    unless %!types{$type}.field($field);

                %!types{$type}.field($field).resolver = $resolver;
            }
            
        }
    }
}

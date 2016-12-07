use Hash::Ordered;

unit module GraphQL::Types;

class GraphQL::Type
{
    has Str  $.name;
    has Str  $.description;
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
    has Set $.possibleTypes is rw;

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

    method Str
    {
        "type $.name " ~ 
            ('implements ' ~ @.interfaces.map({.name}).join(', ') ~ ' '
                if @.interfaces)
        ~ "\{\n" ~
        $.fields.values.grep({.name !~~ /^__/}).map({'  ' ~ .Str}).join("\n")
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

class GraphQL::Field is GraphQL::Type
{
    has GraphQL::Type $.type is rw;
    has GraphQL::InputValue @.args is rw;
    has Bool $.isDeprecated = False;
    has Str $.deprecationReason;
    has Callable $.resolver is rw;

    method Str
    {
        "$.name" ~
            ('(' ~ @!args.join(', ') ~ ')' if @!args)
        ~ ": $!type.name()"
    }

    method resolve(:$objectValue, :%argumentValues, :$schema)
    {
        unless $!resolver.defined
	{
	    say "No resolver, trying default";
	}

        #
        # To provide a lot of flexibility in how the resolver
        # gets called, introspect it and try to give it what
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
                            if $param_name eq 'schema'
                            {
                                %args<schema> = $schema;
                                last;
                            }
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
    has Set $.possibleTypes is rw;

    method Str
    {
        "union $.name = "
            ~ $.possibleTypes.keys.map({ $_.name }).join(' | ')
            ~ "\n"
    }
}

class GraphQL::EnumValue is GraphQL::Scalar
{
    has Bool $.isDeprecated = False;
    has Str $.deprecationReason;

    method Str { $.name }
}

class GraphQL::Enum is GraphQL::Scalar
{
    has Str $.kind = 'ENUM';
    has Set $.enumValues;

    method Str
    {
        "enum $.name \{\n" ~
            $.enumValues.keys.map({ "  $_.Str()"}).join("\n") ~
        "\n}\n";
    }
}

enum GraphQL::DirectiveLocation<QUERY MUTATION FIELD FRAGMENT_DEFINITION
   FRAGMENT_SPREAD INLINE_FRAGMENT>;

class GraphQL::Directive is GraphQL::Type
{
    has GraphQL::DirectiveLocation @.locations;
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
            @.selectionset.map({.Str('  ')}).join("\n") ~
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
}

class GraphQL::FragmentSpread
{
    has Str $.name;
    has @.directives;
}

class GraphQL::InlineFragment
{
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
        %.operations.values.map({.Str}).join("\n") ~
        %.fragments.values.map({.Str}).join("\n") ~ "\n";
    }
}

class GraphQL::Schema
{
    has %.types;
    has $.query is rw;
    has $.mutation is rw;
    has $.subscription is rw;

    method type($query = $!query) { %!types{$query} }

    method BUILD(:%types, :$!query = 'Query', :$!mutation, :$!subscription)
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

        $str ~= "schema \{\n  query: $.query\n}\n";
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
                    unless %!types{$type}.fields{$field};

                %!types{$type}.fields{$field}.resolver = $resolver;
            }
            
        }
    }
}

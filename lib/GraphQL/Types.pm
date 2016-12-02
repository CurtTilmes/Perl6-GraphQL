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

class GraphQL::Object is GraphQL::Type
{
    has Str $.kind = 'OBJECT';
    has Hash::Ordered $.fields;
    has GraphQL::Type @.interfaces is rw;

    method Str
    {
        "type $.name " ~ 
            ('implements ' ~ @.interfaces.map({.name}).join(', ') ~ ' '
                if @.interfaces)
        ~ "\{\n" ~
        $.fields.values.map({'  ' ~ .Str}).join("\n") ~
        "\n}\n"
    }
}

class GraphQL::InputValue is GraphQL::Object
{
    has GraphQL::Type $.type is rw;
    has $.defaultValue;

    method Str
    {
        "$.name: $.type.name()" ~ (" = $.defaultValue" if $.defaultValue)
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
            ('(' ~ @.args.join(', ') ~ ')' if @.args)
        ~ ": $.type.name()"
    }

    method resolve($objectValue, %argumentValues)
    {
        given $!resolver.arity
        {
            when 0 { $!resolver() }
            when 1 { $!resolver($objectValue) }
            when 2 { $!resolver($objectValue, %argumentValues) }
        }
    }
}

class GraphQL::Interface is GraphQL::Type
{
    has Str $.kind = 'INTERFACE';
    has Hash::Ordered $.fields;

    method Str
    {
        "interface $.name \{\n" ~
            $!fields.values.map({"  " ~ .Str}).join("\n") ~
        "\n}\n"
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

class GraphQL::Enum is GraphQL::Scalar
{
    has Str $.kind = 'ENUM';
    has Set $.enumValues;

    method Str
    {
        "enum $.name \{\n" ~
            $.enumValues.keys.map({ "  $_"}).join("\n") ~
        "\n}\n";
        
    }
}

# Make this a real GraphQL Enum?
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

my %defaultTypes =
    Int     => $GraphQLInt,
    Float   => $GraphQLFloat,
    String  => $GraphQLString,
    Boolean => $GraphQLBoolean,
    ID      => $GraphQLID,

    __Schema => GraphQL::Object.new(
        name => '__Schema',
        fields => Hash::Ordered.new()
    ),

    __Type => GraphQL::Object.new(
        name => '__Type',
        fields => Hash::Ordered.new()
    ),

    __TypeKind => GraphQL::Enum.new(
        name => '__TypeKind',
        enumValues => set ()
    ),

    __Field => GraphQL::Object.new(
        name => '__Field',
        fields => Hash::Ordered.new()
    ),

    __EnumValue => GraphQL::Object.new(
        name => '__EnumValue',
        fields => Hash::Ordered.new()
    ),

    __InputValue => GraphQL::Object.new(
        name => '__InputValue',
        fields => Hash::Ordered.new()
    ),
    
    __Directive => GraphQL::Directive.new();

class GraphQL::Argument
{
    has $.name;
    has $.value;

    method Str { "$.name: $.value" }
}

class GraphQL::Operation
{
    has Str $.operation = 'query';
    has Str $.name;
    has %.vars;
    has %.directives;
    has @.selectionset;

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
    has GraphQL::Argument @.args;
    has GraphQL::Directive @.directives;
    has @.selectionset;

    method responseKey { $!alias // $!name }

    method Str(Str $indent = '')
    {
        $indent ~ ($.alias ~ ': ' if $.alias) ~ $.name ~
        ('(' ~ @.args.map({.Str}).join(', ') ~')' if @.args.elems) ~
            (" \{\n" ~ @.selectionset
                        .map({.Str($indent ~ '  ')})
                        .join("\n") 
                 ~ $indent ~ '}' if @.selectionset.elems) 
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
    has %.types is rw = %defaultTypes;
    has $.query is rw = 'Query';
    has $.mutation is rw;
    has $.subscription is rw;

    method type($query = $!query) { %!types{$query} }

    method Str
    {
        my $str = '';

        for %!types.kv -> $typename, $type
        {
            next if %defaultTypes{$typename}.defined;
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

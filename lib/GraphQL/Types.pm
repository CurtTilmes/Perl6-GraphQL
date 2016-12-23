unit module GraphQL::Types;
use Text::Wrap;

subset ID of Cool is export;

class GraphQL::InputObject {}

class GraphQL::Type
{
    has Str $.name;
    has Str $.description;

    method add-comment-description($/)
    {
        return unless $<Comment>;
        $!description = $<Comment>».made.join(' ');
    }

    method description-comment(Str $indent = '')
    {
        return '' unless $!description;

        $indent ~ wrap-text($!description, :prefix("$indent# ")) ~ "\n";
    }

    method Str { $!name }
}

# This is a placeholder for types not yet defined.
# It will get replaced later.
class GraphQL::LazyType is GraphQL::Type
{
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

class GraphQL::Scalar is GraphQL::Type
{
    has Str $.kind = 'SCALAR';

    method Str { self.description-comment ~ "scalar $.name\n" }

    method to-json($name, $value, $indent)
    {
        qq<$indent"$name": > ~ ($value.defined ?? qq<"$value"> !! 'null')
    }
}

class GraphQL::String is GraphQL::Scalar
{
    has Str $.name = 'String';

    method coerce($value) { $value.Str }
}

class GraphQL::Int is GraphQL::Scalar
{
    has Str $.name = 'Int';

    method to-json($name, $value, $indent)
    {
        qq<$indent"$name": {$value}>
    }

    method coerce($value) { $value.Int }
}

class GraphQL::Float is GraphQL::Scalar
{
    has Str $.name = 'Float';

    method to-json($name, $value, $indent)
    {
        qq<$indent"$name": {$value}>
    }

    method coerce($value) { $value.Num }
}

class GraphQL::Boolean is GraphQL::Scalar
{
    has Str $.name = 'Boolean';

    method to-json($name, $value, $indent)
    {
        qq<$indent"$name": "{$value ?? 'true' !! 'false'}">
    }

    method coerce($value) { $value }
}

class GraphQL::ID is GraphQL::Scalar
{
    has Str $.name = 'ID';

    method coerce($value) { $value }
}

#
# Default Types
#
our $GraphQLString  is export = GraphQL::String.new;
our $GraphQLFloat   is export = GraphQL::Float.new;
our $GraphQLInt     is export = GraphQL::Int.new;
our $GraphQLBoolean is export = GraphQL::Boolean.new;
our $GraphQLID      is export = GraphQL::ID.new;

class GraphQL::List is GraphQL::Type
{
    has Str $.kind = 'LIST';
    has GraphQL::Type $.ofType is rw;
    
    method name { '[' ~ $.ofType.name ~ ']' }

    method to-json($name, $value, $indent)
    {
        qq<$indent"$name": \[\n> ~
            $value.map({ $!ofType.to-json(Str, $_, $indent ~ '  ') })
                  .join(",\n") ~
        qq<\n$indent]>
    }

    method coerce($value)
    {
        say "coercing a list!";
    }
}

class GraphQL::Non-Null is GraphQL::Type
{
    has Str $.kind = 'NON_NULL';
    has GraphQL::Type $.ofType is rw;

    method name { $!ofType.name ~ '!' }

    method Str  { $!ofType.Str  ~ '!' }

    method coerce($value)
    {
        die "Null in Non-Null field" unless $value.defined;
        $!ofType.coerce($value)
    }

    method to-json($name, $value, $indent)
    {
        $!ofType.to-json($name, $value, $indent);
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

class GraphQL::Field is GraphQL::Type does Deprecatable
{
    has GraphQL::Type $.type is rw;
    has GraphQL::InputValue @.args is rw;
    has Callable $.resolver is rw;

    method Str(Str $indent = '')
    {
        self.description-comment($indent) ~
        "$indent$.name" ~
            ('(' ~ @!args.join(', ') ~ ')' if @!args)
        ~ ": $!type.name()" ~ self.deprecate-str
    }
}

role HasFields
{
    has GraphQL::Field @.fieldlist;

    method field(Str $name)
    {
        @!fieldlist.first: *.name eq $name;
    }

    method fields(Bool :$includeDeprecated)
    {
	@!fieldlist.grep: {.name !~~ /^__/ and
                            ($includeDeprecated or not .isDeprecated) }
    }

    method fields-str (Str $indent = '')
    {
        self.fields(:includeDeprecated).map({.Str($indent)}).join("\n")
    }
}

class GraphQL::Interface is GraphQL::Type does HasFields
{
    has Str $.kind = 'INTERFACE';
    has GraphQL::Type @.possibleTypes;

    method Str
    {
        self.description-comment ~
        "interface $.name \{\n" ~ self.fields-str('  ') ~ "\n}\n"
    }
}

class GraphQL::Object is GraphQL::Type does HasFields
{
    has Str $.kind = 'OBJECT';
    has GraphQL::Type @.interfaces is rw;

    method addfield($field) { push @!fieldlist, $field }
    
    method fragment-applies(Str $fragmentType) returns Bool
    {
        return True if $fragmentType eq $.name;
        die "Check FragmentType in interfaces"; # need to add more checks
    }

    method Str
    {
        self.description-comment ~
        "type $.name " ~ 
            ('implements ' ~ (@!interfaces».name).join(', ') ~ ' '
                if @.interfaces)
        ~ "\{\n" ~ self.fields-str('  ') ~ "\n}\n"
    }

    method to-json($name, $value, $indent)
    {
        $indent ~ (qq<"$name": > if $name) ~

        ($value

        ?? "\{\n" ~
                $value.map({ .to-json($indent ~ '  ') }).join(",\n") ~
            qq<\n$indent}>

        !! 'null')
    }

}

class GraphQL::InputObjectType is GraphQL::Type
{
    has Str $.kind = 'INPUT_OBJECT';
    has GraphQL::InputValue @.inputFields;
    has $.class;

    method Str
    {
        self.description-comment ~
        "input $.name " ~
        ~ "\{\n" ~ @!inputFields.map({'  ' ~ .Str}).join("\n") ~ "\n}\n"
    }

    method coerce(%value)
    {
        return $!class.new(|%value) if $!class ~~ GraphQL::InputObject;

        my %c;
        for @!inputFields -> $f
        {
            %c{$f.name} = $f.type.coerce(%value{$f.name})
                if %value{$f.name}:exists;
        }
        return %c;
    }
}

class GraphQL::Union is GraphQL::Type
{
    has $.kind = 'UNION';
    has GraphQL::Type @.possibleTypes;

    method Str
    {
        self.description-comment ~
        "union $.name = {(@!possibleTypes».name).join(' | ')}\n";
    }
}

class GraphQL::EnumValue is GraphQL::Scalar does Deprecatable
{
    
    method Str(Str $indent = '')
    { self.description-comment ~ "$indent$.name" ~ self.deprecate-str }
}

class GraphQL::Enum is GraphQL::Type
{
    has Str $.kind = 'ENUM';
    has GraphQL::Type @.enumValues;

    method enumValues(Bool :$includeDeprecated)
    {
	@!enumValues.grep: { $includeDeprecated or not .isDeprecated }
    }
    
    method valid($value) returns Bool
    {
        return Nil unless $value.defined;
        so @.enumValues.first({ .name eq $value });
    }

    method Str
    {
        self.description-comment ~
        "enum $.name \{\n" ~
            @!enumValues.map({ $_.Str('  ')}).join("\n") ~
        "\n}\n";
    }

    method to-json($name, $value, $indent)
    {
        qq<$indent"$name": > ~ ($value.defined ?? qq<"$value"> !! 'null')
    }
}

class GraphQL::Directive is GraphQL::Type
{
    has GraphQL::EnumValue @.locations;
    has GraphQL::InputValue @.args;
}

class GraphQL::Variable
{
    has Str $.name;
    has GraphQL::Type $.type;
    has $.defaultValue;

    method Str
    {
        "\$$!name: $!type.name()" ~
            (" = $!defaultValue" if $!defaultValue.defined)
    }
}

class GraphQL::Operation
{
    has Str $.name;
    has Str $.operation = 'query';
    has GraphQL::Variable @.vars;
    has GraphQL::Directive @.directives;
    has @.selectionset;  # QueryField or Fragment

    method Str
    {
        ("$.operation $.name " if $.name) ~
        ( '(' ~ @.vars.map({.Str}).join(', ') ~ ') ' if @.vars) ~ "\{\n" ~
            @.selectionset.map({.Str('  ')}).join('') ~
        "}\n"
    }
}

sub directive-str($name, $args)
{
    ' @' ~ $name ~ ('('
                        ~ $args.keys
                               .map({ "$_: \$" ~ $args{$_}.name})
                               .join(', ')
                   ~ ')' if $args)
}

sub argvalue($val)
{
    given $val
    {
        when Hash
        {
            '{ ' ~ $val.keys.map({ "$_: " ~ argvalue($val{$_})}) ~ ' }'
        }
        when Array
        {
            ...
        }
        when GraphQL::Variable
        {
            "\$$val.name()";
        }
        when Bool
        {
            $val.defined ?? ($val ?? 'true' !! 'false')
                         !! 'null'
        }
        default
        {
            $val.perl
        }
    }
}

class GraphQL::QueryField
{
    has Str $.alias;
    has Str $.name;
    has %.args;
    has %.directives;
    has @.selectionset;

    method responseKey { $!alias // $!name }

    method Str(Str $indent = '')
    {
        $indent ~ ($!alias ~ ': ' if $!alias) ~ $!name
        ~
            ( '(' ~ %!args.keys.map({$_.Str ~ ': ' ~ argvalue(%!args{$_})})
                               .join(', ') ~ ')' if %!args)
        ~
            %!directives.kv.map(&directive-str)
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
    has %.directives;
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
    has %.directives;

    method Str($indent = '')
    {
        "$indent... $.name\n"
    }
}

class GraphQL::InlineFragment
{
    has Str $.onType;
    has %.directives;
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
        if $operationName
        {
            return %!operations{$operationName}
                if %!operations{$operationName};

            die "Must provide an operation.";
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


use GraphQL::Types;

unit module GraphQL::Response;

class GraphQL::Response
{
    has Str $.name;
    has GraphQL::Type $.type;
    has $.value;
    
    method to-json(Str $indent = '')
    {
        $!value = await $!value if $!value ~~ Promise;

        $!type.to-json($!name, $!value, $indent);
    }
}

class GraphQL::Error is GraphQL::Response
{
    has Str $.message;
    has Str @.locations;

    method to-json(Str $indent = '')
    {
        qq{$indent"message": "$!message"};
    }
}

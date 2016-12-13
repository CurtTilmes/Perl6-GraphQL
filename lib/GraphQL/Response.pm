unit module GraphQL::Response;

class GraphQL::Response
{
    has Str $.name;
    has GraphQL::Type $.type;
    has $.value;
    
    method to-json {...}
}

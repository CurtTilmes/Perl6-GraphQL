use Cro::HTTP::Router;
use GraphQL::GraphiQL;
use GraphQL;

sub graphiql() is export {
    content 'text/html', $GraphiQL;
}

sub graphql(GraphQL::Schema $schema) is export {
    request-body -> % (:$query, :$operationName, :$variables)
    {
        content 'application/json', $schema.execute($query,
            operationName => $operationName // Str,
            variables => $variables // %()).to-json;
    }
}

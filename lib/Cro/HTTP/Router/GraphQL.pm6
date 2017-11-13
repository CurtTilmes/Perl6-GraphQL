use Cro::HTTP::Router;
use GraphQL::GraphiQL;
use GraphQL;

sub graphiql() is export {
    content 'text/html', $GraphiQL;
}

sub graphql(GraphQL::Schema $schema) is export {
    request-body -> % (:$query, :$operationName = Str, :$variables)
    {
        content 'application/json', $schema.execute($query,
            :$operationName, variables => $variables // %()).to-json;
    }
}

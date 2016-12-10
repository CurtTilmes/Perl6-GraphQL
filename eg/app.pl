use Bailador;
use GraphQL;
use JSON::Fast;

my $schema = GraphQL::Schema.new('
type Query {
  hello: String
}');

$schema.resolvers({
    Query => { hello => sub { 'Hello World' } }
});

sub graphql-query($query)
{
    to-json(GraphQL-ExecuteRequest(:$schema, $query));
}

get '/graphql' => sub {
    graphql-query(request.params<query>);
}

post '/graphql' => sub {
    graphql-query(from-json(request.body)<query>);
}

baile;

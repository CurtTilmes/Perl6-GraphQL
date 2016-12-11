use Bailador;
use GraphQL;
use GraphQL::GraphiQL;

use JSON::Fast;

my $schema = GraphQL::Schema.new('
type Query {
  hello: String
}',
resolvers => 
{
    Query => { hello => sub { 'Hello World' } }
}
);

get '/graphql' => sub { $GraphiQL }

post '/graphql' => sub {
    to-json($schema.execute(from-json(request.body)<query>));
}

baile;

use GraphQL;
use JSON::Fast;

my $schema = GraphQL::Schema.new('type Query { hello: String }',
    resolvers => { Query => { hello => sub { 'Hello World' } } });

sub MAIN(Str $query)
{
    say to-json $schema.execute($query);
}

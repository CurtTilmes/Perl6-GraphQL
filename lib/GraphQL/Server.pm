use Bailador;
use JSON::Fast;
use GraphQL;
use GraphQL::GraphiQL;

my $schema;

sub GraphQL-Server($s) is export
{
    $schema = $s;

    get '/' => sub { redirect('/graphql') }

    get '/graphql' => sub { $GraphiQL }
    
    post '/graphql' => sub {
        to-json($schema.execute(from-json(request.body)<query>));
    }
}

sub MAIN(Str $query?, :$port = 3000) is export
{
    if $query
    {
        say to-json $schema.execute($query);
    }
    else
    {
        baile $port;
    }
}

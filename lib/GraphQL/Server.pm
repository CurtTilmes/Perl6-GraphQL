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

multi sub MAIN(Str:D $query) is export
{
    say "Running query [$query]";
    
    say to-json $schema.execute($query);
}

multi sub MAIN(Str:D :$filename) is export
{
    say "getting query from [$filename]";
    say to-json $schema.execute($filename.IO.slurp);
}

multi sub MAIN(Int :$port = 3000) is export
{
    baile $port;
}

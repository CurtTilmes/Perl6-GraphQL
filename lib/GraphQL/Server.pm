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
        $schema.execute(from-json(request.body)<query>).to-json
    }
}

multi sub MAIN(Str:D $query) is export
{
    say $schema.execute($query).to-json;
}

multi sub MAIN(Str:D :$filename) is export
{
    say $schema.execute($filename.IO.slurp).to-json;
}

multi sub MAIN(Int :$port = 3000) is export
{
    baile $port;
}

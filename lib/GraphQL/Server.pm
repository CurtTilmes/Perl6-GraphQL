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
        my $request = from-json(request.body);
        my $operationName = $request<operationName>;
        my %variables = $request<variables> // ();
        content_type('application/json');
        $schema.execute($request<query>, :%variables, http-request => request,
                        |(:$operationName if $operationName)).to-json
    }
}

multi sub MAIN(Str:D $query) is export
{
    say $schema.execute($query).to-json;
}

multi sub MAIN(Bool:D :$print) is export
{
    print $schema;
}

multi sub MAIN(Str:D :$filename) is export
{
    say $schema.execute($filename.IO.slurp).to-json;
}

multi sub MAIN(Int :$port = 3000) is export
{
    baile;
}

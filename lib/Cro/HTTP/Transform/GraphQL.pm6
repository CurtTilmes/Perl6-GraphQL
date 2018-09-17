use Cro::HTTP::Request;
use Cro::HTTP::Response;
use Cro::Transform;

use GraphQL::GraphiQL;
use GraphQL;

unit class Cro::HTTP::Transform::GraphQL does Cro::Transform;

has GraphQL::Schema $.schema;
has Bool $.graphiql;

method consumes() { Cro::HTTP::Request  }
method produces() { Cro::HTTP::Response }

method transformer(Supply:D $requests --> Supply)
{
    supply whenever $requests -> $request
    {
        my $response = Cro::HTTP::Response.new(status => 404, :$request);

        given $request.method
        {
            when 'GET'
            {
                if $!graphiql
                {
                    given $response
                    {
                        .status = 200;
                        .append-header('Content-type', 'text/html');
                        .set-body($GraphiQL);
                    }
                }
            }
            when 'POST'
            {
                with await $request.body
                {
                    my $content = $!schema.execute(
                        .<query>,
                        operationName => .<operationName> // Str,
                        variables => .<variables> // %()).to-json;

                    given $response
                    {
                        .status = 200;
                        .append-header('Content-type',
                                       'application/json; charset=utf-8');
                        .set-body: $content;
                    }
                }
            }
        }

        emit $response;
    }
}

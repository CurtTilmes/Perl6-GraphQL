#!/usr/bin/env perl6

use GraphQL;
use Cro::HTTP::Router::GraphQL;
use Cro::HTTP::Router;
use Cro::HTTP::Server;

class Query
{
    method hello(--> Str) { 'Hello World' }
}

my $schema = GraphQL::Schema.new(Query);

my Cro::Service $hello = Cro::HTTP::Server.new:
    :host<localhost>, :port<10000>,
    application => route
    {
        get -> { redirect '/graphql' }

        get -> 'graphql' { graphiql }

        post -> 'graphql' { graphql($schema) }
    }

$hello.start;

react whenever signal(SIGINT) { $hello.stop; exit; }

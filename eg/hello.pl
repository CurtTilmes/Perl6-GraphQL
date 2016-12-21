#!/usr/bin/env perl6

use GraphQL;
use GraphQL::Server;

class Query
{
    method hello(--> Str) { 'Hello World' }
}

my $schema = GraphQL::Schema.new(Query);

GraphQL-Server($schema);

#!/usr/bin/env perl6

use GraphQL;
use GraphQL::Server;

my $schema = GraphQL::Schema.new('type Query { hello: String }',
    resolvers => { Query => { hello => sub { 'Hello World' } } });

GraphQL-Server($schema);

Perl 6 GraphQL
==============

A [Perl 6](https://perl6.org/) implementation of the
[GraphQL](http://graphql.org/) standard.  GraphQL is a query language
for APIs originally created by Facebook.

## Intro

Before we get into all the details, here's the Perl 6 GraphQL "Hello World"

```
use GraphQL;
use JSON::Fast;

my $schema = GraphQL::Schema.new('type Query { hello: String }',
    resolvers => { Query => { hello => sub { 'Hello World' } } });

sub MAIN(Str $query)
{
    say to-json $schema.execute($query);
}
```

You can run this on the command line:
```
% perl6 hello.pl 
Usage:
  hello.pl <query> 
% perl6 hello.pl '{hello}'
{
  "data": {
    "hello": "Hello World"
  }
}
```

You can even ask for information about the schema and types:
```
% perl6 hello.pl '{__schema {types{name fields{name}}}}'
{
  "data": {
    "__schema": {
      "types": [
        {
          "name": "Query",
          "fields": [
            {
              "name": "hello"
            }
          ]
        }
      ]
    }
  }
}
```

That's fine for the command line, but you can also easily wrap GraphQL
into a web server to expose that API to external clients.  If you have
the Perl 6 web framework
[Bailador](https://github.com/ufobat/Bailador), you can do that like this:

```
use Bailador;
use GraphQL;
use GraphQL::GraphiQL;
use JSON::Fast;

my $schema = GraphQL::Schema.new('type Query { hello: String }',
    resolvers => { Query => { hello => sub { 'Hello World' } } });

get '/graphql' => sub { $GraphiQL }

post '/graphql' => sub {
    to-json($schema.execute(from-json(request.body)<query>));
}

baile;
```

This says whenever someone sends an HTTP POST to the server path
"/graphql", execute it with the schema, encode the resulting data
structure with JSON and send it back.

There is one additional feature.  If it receives a GET request to
"/graphql", send back the
[GraphiQL](https://github.com/graphql/graphiql) graphical interactive
in-browser GraphQL IDE.

![](eg/hello-graphiql.png)

You can use that to explore the schema (though the Hello World schema
is very simple, that won't take long), and interactively construct and
execute GraphQL queries.

A real production implementation would do a lot more, setting
content-types, taking queries on GET as well as POST, etc.

See [eg/usersexample.md](https://github.com/golpa/Perl6-GraphQL/blob/master/eg/usersexample.md) for a more complicated example.


Perl 6 GraphQL


Just getting started...

Doesn't do variables, directives, introspection, fragments, etc., etc. but it
will print out "Hello World" if you run this:


```
use JSON::Fast;
use GraphQL;
use Test;

my $schema = build-schema('
type Query {
  hello: String
}
');

$schema.resolvers(
{
    Query => { hello => sub { 'Hello World' } }
});

my $query = parse-query('
{
   hello
}
');

my $ret = ExecuteRequest(:$schema, :$query)
    or die;

say to-json($ret);
```

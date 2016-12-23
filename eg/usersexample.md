# Users example

The __Schema__ describes the interface for your application in detail.

You start by describing your __Schema__ in terms of data types.
Starting with the GraphQL core types (String, Int, Float, Boolean,
ID), possibly modified ([List], Non-Null!), and built into a set of
Object Types.  You can also define types that are Unions of other
types or Enum enumerations of pre-defined values.

For example:
```
type User {
  id: ID!
  name: String
  birthday: String
  status: Boolean
}
```

I've used 'String' as the type for birthday.  There isn't a core
GraphQL 'Date' or 'DateTime' type -- though other languages frequently
implement it.  We'll probably add that to the Perl6 version soon.  For
this example, it is just a string.

### Descriptions

Though not (yet) part of the standard, another frequently implemented
extension is the ability to add descriptions to types and fields with
\# comments.  If you look at the
[eg/users.schema](https://github.com/golpa/Perl6-GraphQL/blob/master/eg/users.schema)
file, you'll see # descriptions for some of the types and fields.
Those descriptions can be queried with the GraphQL introspection
queries through the meta types and queries __Schema, __Type, etc.  The
GraphiQL IDE displays them while you explore the schema with the Docs
functionality.

## Types with arguments

Object fields can also include arguments.  To query our User database,
we'll define two such queries:

```
type Query {
  listusers(start: ID = "0", count: Int = "1"): [User]
  user(id: ID!): User
}
```

So you can list *count* users starting with a specific *id*, or just
query a single user.

## Resolvers

Now that we've defined the external GraphQL API, we need to define
functions that resolve those queries.

First a Perl class to act like our GraphQL *User* type:

```
class User
{
    has Int $.id is rw;
    has Str $.name is rw;
    has Str $.birthday is rw;
    has Bool $.status is rw;
}
```

and a pseudo-database to hold our users:
```
my @users = User.new(id => 0, name => '...', birthday => '...', status => True),
            User.new(...),
            ...;
```

Then a few simple functions to implement listusers() and user(),
matching the argument list defined in the GraphQL schema:

```
my $resolvers = 
{
    Query =>
    {
        listusers => sub (:$start, Int :$count)
        {
            @users[$start ..^ $start+$count]
        },

        user => sub (:$id)
        {
            @users[$id]
        }
    }
};
```

*user()* just returns the user specified by $id, and *listusers()*
returns *count* of them starting with id *start* and returns them in
an *Array* which gets mapped to the GraphQL *List*.

Then create your GraphQL::Schema :

```
my $schema = GraphQL::Schema.new(...schema here..., resolvers => $resolvers);
```

If you put your schema in a separate file, you can plug it in easily
with IO.slurp (see the
[example](https://github.com/golpa/Perl6-GraphQL/blob/master/eg/usersserver.pl)).


Running this server under
[Bailador](https://github.com/ufobat/Bailador), you can explore the
schema interactively, and execute our queries.  For example:

```
{
  user(id: 0) {
    name
    birthday
  }
}
```

to see the name and birthday of user 0.

Note that in the **hello** example, the resolver was specified down to
the *Field* level returning a *Scalar* (*String*), while here, the
resolvers return an *Object* or a *List* of *Object*s.  If you return
a Perl 6 Class, it must include methods for resolving each field of
the type.  (e.g. here, we have methods for name(), birthday(),
etc. defined by Perl because they are public).  You can actually mix
and match if you like, defining individual resolvers for some fields,
while relying on Class methods for others.  If you want to define
both, you'll have to call $schema.resolvers() multiple times, once
with the resolver for the *Object* level, and once for the fields of
that object.

## Mutations

Querying is nice, but what if you want to allow changes? (Hopefully
only by trusted, authenticated, authorized users.)

In reality, there isn't really anything special about Mutations, and
if you wanted to do an update with a normal query, nothing technical
would stop you.  It is highly recommended, however, that you group such
queries and explicitly declare them as mutations.  This has a few real
consequences.  For one, the server will always execute mutations
serially though it is allowed to execute normal queries in parallel.
This will prevent race conditions and race induced non-deterministic
behaviors.  For another, client tools can assume that normal queries
can be cached, while mutations never will be.

We can define a special kind of object called an *InputObject*, that
looks almost like a normal type:

```
input UserInput {
    name: String
    birthday: String
    status: Boolean
}
```

and define some mutations in the schema:

```
type Mutation {
  adduser(newuser: UserInput!): ID
  updateuser(id: ID!, userinput: UserInput!): User
}
```

and implement some matching resolvers for those:

```
adduser => sub (:%newuser)
{
    push @users, User.new(id => @users.elems, |%newuser);
    return @users.elems - 1;
},

updateuser => sub (:$id, :%userinput)
{
    for %userinput.kv -> $k, $v
    {
        @users[$id]."$k"() = $v;
    }

    return @users[$id]
}
```

See the full schema in
[users.schema](https://github.com/golpa/Perl6-GraphQL/blob/master/eg/users.schema),
and the example Bailador server in
[usersserver.pl](https://github.com/golpa/Perl6-GraphQL/blob/master/eg/usersserver.pl).

## Some sample queries

List the first three users, with their names:
```
{
  listusers(count:3) {
    name
  }
}
```

Get the birthday and status for user 2:
```
{
  user(id: 2){
    birthday
    status
  }
}
```

Add a new user named "John" (null status and birthday because they
aren't specified)
```
mutation {
  adduser(newuser: {name: "John"})
}
```

Set John's birthday to "Every Year", and return his name and birthday:
```
mutation {
  updateuser(id: "5", userinput: { birthday: "Every Year" }) {
    name
    birthday
  }
}
```

## Notes

Again, this isn't really a production quality server.  You should do
more with authentication/authorization, sessions, setting
content-types, etc.  This server also ignores variables supplied by
the user.  Those should also be passed in to the schema execute()
call.  In the future, some more of that work may be added in to this
repository.

Also parsing in Perl 6 is still very slow, so a simple optimization is
to cache parsed documents, and just re-use the parsed document if the
same query is sent.  (When you build GraphQL into User interfaces, the
same query documents are frequently reused.)

You can see how that would work:.

Instead of:
```
$schema.execute('some query');
```

use the .document() method to parse it, and the :document named
parameter to execute to specify an already parsed document (a
*GraphQL::Document*).

```
my $document = $schema.document('some query');
$schema.execute(:$document);
```

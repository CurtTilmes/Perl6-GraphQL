unit module GraphQL;

use GraphQL::Introspection;
use GraphQL::Grammar;
use GraphQL::Actions;
use GraphQL::Types;
use GraphQL::Response;
use GraphQL::Execution;
use GraphQL::Validation;

multi sub trait_mod:<is>(Method $m, :$graphql-background!) is export { ... }

my Set $defaultTypes = set GraphQLInt, GraphQLFloat, GraphQLString,
                           GraphQLBoolean, GraphQLID;

class GraphQL::Schema
{
    has GraphQL::Type %!types;
    has GraphQL::Directive @.directives;
    has Str $.query is rw = 'Query';
    has Str $.mutation is rw;
    has Str $.subscription is rw;
    has %.stash is rw;
    has @.errors;
    has $!resolved-schema;

    multi method new(:$query, :$mutation, :$subscription, :$resolvers, *@types,
        *%stash-vars)
        returns GraphQL::Schema
    {
        my $schema = GraphQL::Schema.bless;
        $schema.stash{%stash-vars.keys} = %stash-vars.values;

        $schema.add-type($defaultTypes.keys);

        my $actions = GraphQL::Actions.new(:$schema);

        GraphQL::Grammar.parse($GraphQL-Introspection-Schema,
                               :$actions,
                               rule => 'TypeSchema')
            or die "Failed to parse Introspection Schema";

        $schema.add-type(@types);

        $schema.query        = $query        if $query;
        $schema.mutation     = $mutation     if $mutation;
        $schema.subscription = $subscription if $subscription;

        $schema.resolvers($resolvers) if $resolvers;

        return $schema;
    }

    multi method new(Str $schemastring, :$resolvers, *%stash-vars)
        returns GraphQL::Schema
    {
        my $schema = GraphQL::Schema.new;
        $schema.stash{%stash-vars.keys} = %stash-vars.values;
        
        my $actions = GraphQL::Actions.new(:$schema);

        GraphQL::Grammar.parse($schemastring, :$actions, :rule('TypeSchema'))
            or die "Failed to parse schema";

        $schema.resolvers($resolvers) if $resolvers;

        return $schema;
    }

    method !add-meta-fields
    {
        self.queryType.addfield(GraphQL::Field.new(
            name => '__type',
            type => self.type('__Type'),
            args => [ GraphQL::InputValue.new(
                          name => 'name',
                          type => GraphQL::Non-Null.new(
                              ofType => GraphQLString
                              )
                          )
                    ],
            resolver => sub (:$name) { self.type($name) }
        ));

        self.queryType.addfield(GraphQL::Field.new(
            name => '__schema',
            type => GraphQL::Non-Null.new(
                ofType => self.type('__Schema')
            ),
            resolver => sub { self }
        ));
    }

    has %!resolved;

    method resolve-type(GraphQL::Type $type)
    {
        return $type if $type ~~ GraphQL::Object and %!resolved{$type.name}++;

        given $type
        {
            when GraphQL::LazyType
            {
                my $realtype = self.type($type.name);

                die "Can't resolve $type.name()"
                    if $realtype ~~ GraphQL::LazyType;

                return $realtype;
            }
            when GraphQL::Interface
            {
                $type.fieldlist .= map({ self.resolve-type($_) });
            }
            when GraphQL::Object
            {
                $type.fieldlist .= map({ self.resolve-type($_) });

                $type.interfaces .= map({ self.resolve-type($_) });

                push $type.fieldlist, GraphQL::Field.new(
                    name => '__typename',
                    type => GraphQLString,
                    resolver => sub { $type.name });

                for $type.interfaces -> $int
                {
                    unless $int.possibleTypes.first($type)
                    {
                        push $int.possibleTypes, $type;
                    }
                }
            }
            when GraphQL::Input
            {
                $type.inputFields .= map({ self.resolve-type($_) });
            }
            when GraphQL::Union
            {
                $type.possibleTypes .= map({ self.resolve-type($_) });;
            }
            when GraphQL::Non-Null | GraphQL::List
            {
                $type.ofType = self.resolve-type($type.ofType);
            }
            when GraphQL::Field
            {
                $type.type = self.resolve-type($type.type);
                $type.args .= map({ self.resolve-type($_) });
            }
            when GraphQL::InputValue
            {
                $type.type = self.resolve-type($type.type);
            }
        }
        return $type;
    }

    method resolve-schema
    {
        die "Must define root query type" unless self.queryType()
            and self.queryType ~~ GraphQL::Object;

        if not $!mutation.defined and self.type('Mutation')
            and self.type('Mutation') ~~ GraphQL::Object
        {
            $!mutation = 'Mutation';
        }

        self!add-meta-fields;

        for %!types.values -> $type
        {
            self.resolve-type($type);
        }
    }

    method types { %!types.values }

    method add-type(*@newtypes)
    {
        for @newtypes
        {
            when GraphQL::Type { %!types{.name} = $_; }

            when GraphQL::InputObject { self.add-inputobject($_) }

            when Enumeration { self.add-enum($_) }

            default { self.add-class($_) }
        }
    }

    method maketype(Str $rule, Str $desc) returns GraphQL::Type
    {
        my $actions = GraphQL::Actions.new(:schema(self));

        GraphQL::Grammar.parse($desc, :$rule, :$actions).made;
    }

    method add-class($t)
    {
        my @fields;

        for $t.^attributes -> $a
        {
            next unless $a.has_accessor;

            my $var = $a ~~ /<-[!]>+$/;

            my $name = $var.Str;

            next unless $name ~~ /^<[_A..Za..z]><[_0..9A..Za..z]>*$/;

            next unless $a.type ~~ Any;

            my $type = self.perl-type($a.type);

            my $description = $a.WHY ?? ~$a.WHY !! Str;

            push @fields, GraphQL::Field.new(:$name, :$type, :$description);
        }

        for $t.^methods -> $m
        {
            next if @fields.first: { $m.name eq .name };

            next if $m.name eq 'new'|'BUILD';

            next unless $m.name ~~ /^<[_A..Za..z]><[_0..9A..Za..z]>*$/;

            my GraphQL::InputValue @args;

            my $sig = $m.signature;

            next unless $sig.returns ~~ Any;

            my $type = self.perl-type($sig.returns);

            for $sig.params -> $p
            {
                next unless $p.named;

                my $name = $p.named_names[0] or next;

                next unless $name ~~ /^<[_A..Za..z]><[_0..9A..Za..z]>*$/;

                next unless $p.type ~~ Any;

                my $type = self.perl-type($p.type);

                $type = GraphQL::Non-Null.new(ofType => $type)
                    unless $p.optional;

                my $defaultValue = $p.default ?? $p.default.() !! Nil;

                push @args, GraphQL::InputValue.new(:$name,
                                                    :$type,
                                                    :$defaultValue);
            }

            my $description = $m.WHY ?? ~$m.WHY !! Str;

            push @fields, GraphQL::Field.new(:name($m.name),
                                             :$type,
                                             :@args,
                                             :resolver($m),
                                             :$description);
        }

        my $description = $t.WHY ?? ~$t.WHY !! Str;

        self.add-type(GraphQL::Object.new(name => $t.^name,
                                          fieldlist => @fields,
                                          :$description));
    }

    method add-inputobject($t)
    {
        my @inputfields;

        for $t.^attributes -> $a
        {
            my $var = $a ~~ /<-[!]>+$/;
            my $name = $var.Str;

            my $type = self.perl-type($a.type);

            my $description = $a.WHY ?? ~$a.WHY !! Str;

            push @inputfields, GraphQL::InputValue.new(:$name,
                                                       :$type,
                                                       :$description);
        }

        my $description = $t.WHY ?? ~$t.WHY !! Str;

        self.add-type(GraphQL::Input.new(name => $t.^name,
                                         inputFields => @inputfields,
                                         class => $t,
                                         :$description));
    }

    method add-enum(Enumeration $t)
    {
        my $description = $t.WHY ?? ~$t.WHY !! Str;

        self.add-type(GraphQL::Enum.new(
                          name => $t.^name,
                          enum => $t,
                          :$description,
                          enumValues => $t.enums.map({
                              GraphQL::EnumValue.new(name => .key)
                          })
                      ));
    }

    method type(Str $name) returns GraphQL::Type
    {
        %!types{$name} // GraphQL::LazyType.new(:$name);
    }

    method perl-type($type, Bool :$nonnull) returns GraphQL::Type
    {
        # There must be a better way...
        if not $nonnull and $type.WHAT.perl ~~ /\:D$/
        {
            return GraphQL::Non-Null.new(
                ofType => self.perl-type($type, :nonnull)
            );
        }

        do given $type
        {
            when Enumeration { self.type(.^name) }

            when Positional
            {
                GraphQL::List.new(ofType => self.perl-type($type.of));
            }

            when Bool   { GraphQLBoolean }
            when Str    { GraphQLString  }
            when Int    { GraphQLInt     }
            when Num    { GraphQLFloat   }
            when Cool   { GraphQLID      }

            default
            {
                self.type(.^name);
            }
        }
    }

    method queryType returns GraphQL::Object
    {
        return  ($!query and %!types{$!query}:exists and
                            %!types{$!query} ~~ GraphQL::Object)
            ?? %!types{$!query}
            !! Nil;
    }

    method mutationType returns GraphQL::Object
    {
        return ($!mutation and %!types{$!mutation})
            ?? %!types{$!mutation}
            !! Nil;
    }

    method subscriptionType returns GraphQL::Object
    {
        return unless $!subscription and %!types{$!subscription};
        %!types{$!subscription}
    }

    method directives { [] }

    method Str
    {
        self.resolve-schema;

        my $str = '';

        for %!types.kv -> $typename, $type
        {
            next if $type ∈ $defaultTypes or $typename ~~ /^__/;
            $str ~= $type.Str ~ "\n";
        }

        $str ~= "schema \{\n";
	$str ~= "  query: $!query\n";
        $str ~= "  mutation: $!mutation\n" if $!mutation;
	$str ~= "}\n";
    }

    method document(Str $query) returns GraphQL::Document
    {
        my $actions = GraphQL::Actions.new(:schema(self));

        GraphQL::Grammar.parse($query, :$actions,
                               rule => 'Document')
            or die "Failed to parse query";
        
        my $document = $/.made;

        self.resolve-schema unless $!resolved-schema++;

        ValidateDocument(:$document, schema => self)
            or die "Document validation failed.";

        return $document;
    }

    method resolvers(%resolvers)
    {
        for %resolvers.kv -> $type, $obj
        {
            die "Undefined object $type" unless %!types{$type};

            for $obj.kv -> $field, $resolver
            {
                die "Undefined field $field for $type"
                    unless %!types{$type}.field($field);
                    
                %!types{$type}.field($field).resolver = $resolver;
            }
        }
    }

    method error(:$message)
    {
        push @!errors, GraphQL::Error.new(:$message);
    }

    method execute(Str $query?,
                   GraphQL::Document :document($doc),
                   Str :$operationName,
                   :%variables,
                   :$initialValue,
                   *%session)
    {
        self.resolve-schema unless $!resolved-schema++;

        %session{%!stash.keys} = %!stash.values;

        @!errors = ();

        my $ret;

        try
        {
            my $document = $doc // self.document($query);

            $ret = ExecuteRequest(:$document,
                                  :$operationName,
                                  :%variables,
                                  :$initialValue,
                                  schema => self,
                                  :%session);

            CATCH {
                default {
                    self.error(message => .Str);
                }
            }
        }

        my @response;

        if $ret
        {
            push @response, GraphQL::Response.new(
                name => 'data',
                type => GraphQL::Object,
                value => $ret
            );
        }

        if @!errors
        {
            push @response, GraphQL::Response.new(
                name => 'errors',
                type => GraphQL::List.new(ofType => GraphQL::Object),
                value => @!errors
            );
        }

        return GraphQL::Response.new(
            type => GraphQL::Object,
            value => @response
        );
    }
}

=begin pod

=head1 GraphQL

=head2 SYNOPSIS

 use GraphQL;

 class Query
 {
     method hello(--> Str) { 'Hello World' }
 }

 my $schema = GraphQL::Schema.new(Query);

 say $schema.execute('{ hello }').to-json;

=head2 DESCRIPTION

"GraphQL is a query language for APIs and a runtime for fulfilling
those queries with your existing data. GraphQL provides a complete and
understandable description of the data in your API, gives clients the
power to ask for exactly what they need and nothing more, makes it
easier to evolve APIs over time, and enables powerful developer
tools." - Facebook Inc., L<B<http://graphql.org>>.

The GraphQL Language is described in detail at
L<B<http://graphql.org>> which also includes the draft specification.
This module is a Perl 6 server implementation of that specification
(or will be once it is complete).  The intent of this documentation
isn't to fully describe GraphQL and its usage, but rather to describe
that Perl implementation and how various functionality is accessible
through Perl.  This document will assume basic awareness of GraphQL
and that standard.

=head2 OVERVIEW

GraphQL itself isn't a database, it is the interface between the
client and whatever database or other data store you use.
Constructing a GraphQL server consists of describing your API
B<Schema> consisting of a data structure of data B<Types>, and
connecting to subroutines or methods for B<Resolution> of the actual
data values.  The B<Schema> is the controller or orchestrator for
everything.  It performs two major functions, B<Validation> to
determine if a query is valid at all, and B<Execution>, which makes
calls to arbitrary code for B<Resolution> to determine the resulting
data structure.  The GraphQL language also specifies B<Introspection>
which is essentially B<Resolution> carried out by the Schema itself to
describe itself.

The synopsis above describes the simplest GraphQL server possible.  It
consists of a single Type or Class called B<Query>, with a single
field in it called I<hello> of type String, with a method attached to
it that returns the string C<Hello World>.

The schema is constructed by passing the Perl 6 class into the
C<GraphQL::Schema>'s C<new()> constructor.  The example then passes in
the simplest GraphQL query K<{hello}>.  Execution will call the
C<hello()> method and return the result in a C<GraphQL::Result>
structure that can then be converted into JSON with C<to-json()>
method which will return the result:

  {
    "data": {
      "hello": "Hello World"
    }
  }

In a typical GraphQL Web server, the query would be HTTP POSTed to an
endpoint at C</graphql> which would call C<GraphQL::Schema.execute()>
and send the resulting JSON string back to the requester.

Each of those steps will be described in more detail below.

=head2 Schema Styles

This module currently supports three different I<styles> for
expressing GraphQL types for your GraphQL schema:

=item B<Manual> - You can construct each type by creating and nesting
various C<GraphQL::*> objects.  

For the "Hello World" example, it would look like this:

=begin code
my $schema = GraphQL::Schema.new(
    GraphQL::Object.new(
        name => 'Query',
        fieldlist => GraphQL::Field.new(
            name => 'hello',
            type => GraphQLString,
            resolver => sub { 'Hello World' }
        )
    )
);
=end code

=item B<GraphQL Schema Language> or B<GSL>- The Perl 6 GraphQL engine
includes a complete parser for the I<GraphQL Schema Language>
described in detail at L<B<http://graphql.org>>.  It is important to
note that this is a U<different> language from the I<GraphQL Query
language> which will be described later.  There is also a handy cheat
sheet for the I<GSL> at
L<https://github.com/sogko/graphql-shorthand-notation-cheat-sheet/>.

For the "Hello World" example, it would look like this:

=begin code
my $schema = GraphQL::Schema.new('type Query { hello: String }',
    resolvers => { Query => { hello => sub { 'Hello World' } } });
=end code

Note that while the schema type descriptions are provided in the
I<GSL>, the resolving functions for each field must be separately
supplied in a two level hash with the names of each Object Type at the
first level, and Field at the second level.

=item B<Direct Perl Classes> - You can also simply pass in Perl 6
classes directly.  A matching schema is constructed by examining the
classes with the Perl language Metamodel for introspection.  Given the
GraphQL type restrictions, not everything you can express in Perl will
result in a valid Schema, so it is important to use only the types as
described below.  Also restrict the names of attributes and methods to
the alpha-numeric and '_'.  (No fancy unicode names, or kebab-case
names.)

For the "Hello World" example, it looks like this:

=begin code
class Query
{
    method hello(--> Str) { 'Hello World' }
}

my $schema = GraphQL::Schema.new(Query);
=end code

Under the hood, the Schemas all look the same, regardless of which
style you use to construct them.  The later two options are just
additional syntactic sugar to make things easier.  You can also mix
and match, making some types one way and some another and everything
will still work fine.

=head2 Types

GraphQL is a strongly, staticly typed language.  Every type must be
defined precisely up front, and all can be checked during validation
phase prior to execution.

The Perl Class hierarchy for GraphQL Types includes these:

=item1 B<GraphQL::Type> (abstract, not to be used directly, only inherited
=item2 B<GraphQL::Scalar>
=item3 B<GraphQL::String>
=item3 B<GraphQL::Int>
=item3 B<GraphQL::Float>
=item3 B<GraphQL::ID>
=item3 B<GraphQL::EnumValue>
=item2 B<GraphQL::List>
=item2 B<GraphQL::Non-Null>
=item2 B<GraphQL::InputValue>
=item2 B<GraphQL::Field>
=item2 B<GraphQL::Interface>
=item2 B<GraphQL::Object>
=item2 B<GraphQL::Input>
=item2 B<GraphQL::Union>
=item2 B<GraphQL::Enum>
=item2 B<GraphQL::Directive>

=head3 I<role> B<Deprecatable>

B<GraphQL::Field> and B<GraphQL::EnumValue> are B<Deprecatable>

They get two extra public attributes C<$.isDeprecated> I<Bool>,
default C<False>, and C<$.deprecationReason> I<Str>.

They also get the method C<.deprecate(Str $reason)>, which defaults to
"No longer supported."

In I<GSL>, you can also deprecate with the directive B<@deprecate> or
C<@deprecate(reason: "something")>.  More on directives below.

=head3 I<role> B<HasFields>

B<GraphQL::Object> and B<GraphQL::Interface> both include a role
B<HasFields> that give them a B<@.fieldlist> array of
B<GraphQL::Field>s, a method B<.field($name)> to look up a field, and
a method B<.fields(Bool :$includeDeprecated)> that will return the
list of fields.  Meta-fields with names starting with "__" are
explicitly not returned in the C<.fields()> list, but can be requested
with C<.field()>.

=head3 B<GraphQL::Type>

This is the main GraphQL type base class.  It has public attributes
C<$.name> and C<$.description>.  It isn't intended to be used
directly, it is just the base class for all the other Types.

The description field can be explicitly assigned in the creation of
each GraphQL::Type.

In I<GSL>, you can set the description field by preceding the
definition of types with comments:

 # Description for mytype
 type mytype {
   # Description for myfield
   myfield: Str
 }

In Perl, the description field is set from the Meto-Object Protocol
$obj.WHY method which by default will be set automatically with Pod
declarations. e.g.

 #| Description for mytype
 class mytype {
   #| Description for myfield
   has Str $.myfield
 }

=head3 B<GraphQL::Scalar> is B<GraphQL::Type>

Serves as the base class for scalar, leaf types.  It adds the method
B<.kind()> = 'SCALAR';

There are several core GraphQL scalar types that map to Perl basic
scalar types:

=begin table
GraphQL Type | Perl Type Class  | Perl Object Instance | Perl Type
===========================================================================
String       | GraphQL::String  | GraphQLString       | Str

Int          | GraphQL::Int     | GraphQLInt          | Int

Float        | GraphQL::Float   | GraphQLFloat        | Num

Boolean      | GraphQL::Boolean | GraphQLBoolean      | Bool

ID           | GraphQL::ID      | GraphQLID           | ID (subset of Cool)
----------------------------------------------------------------------------
=end table

The Perl Object Instances are just short hand pre-created objects that
can be used since those types are needed so frequently.

For example, GraphQL::String.new creates a String type, but you can
just use GraphQLString which is already made.

You can create your own additional scalar types as needed:

  my $URL = GraphQL::Scalar.new(name => 'URL');

or in I<GSL>:

  scalar URL

=head4 B<GraphQL::String> is B<GraphQL::Scalar>

Core String type, maps to Perl type C<Str>.

You can create your own:

 my $String = GraphQL::String.new;

or just use C<GraphQLString>.

=head4 B<GraphQL::Int> is B<GraphQL::Scalar>

Core Int type, maps to Perl type C<Int>.

You can create your own:

 my $Int = GraphQL::Int.new;

or just use C<GraphQLInt>.

=head4 B<GraphQL::Float> is B<GraphQL::Scalar>

Core Float type, maps to Perl type C<Num>.

You can create your own:

 my $Float = GraphQL::Float.new;

or just use C<GraphQLFloat>.

=head4 B<GraphQL::Boolean> is B<GraphQL::Scalar>

Core Boolean type, maps to Perl type C<Bool>.

You can create your own:

 my $Boolean = GraphQL::Boolean.new;

or just use C<GraphQLBoolean>.

=head4 B<GraphQL::ID> is B<GraphQL::Scalar>

Core ID type, maps to Perl type C<ID> which is a subset of C<Cool>.

You can create your own:

 my $ID = GraphQL::ID.new;

or just use C<GraphQLID>.

=head4 B<GraphQL::EnumValue> is B<GraphQL::Scalar> does B<Deprecatable>

The individual enumerated values of an C<Enum>, represented as quoted
strings in JSON.

  my $enumvalue = GraphQL::EnumValue.new(name => 'SOME_VALUE');

They can also be deprecated:

  my $enumvalue = GraphQL::EnumValue.new(name => 'SOME_VALUE',
                                         :isDeprecated,
                                         reason => 'Just because');

or can be later deprecated:

  $enumvalue.deprecate('Just because');

See B<GraphQL::Enum> for more information about creating EnumValues.

=head4 B<GraphQL::List> is B<GraphQL::Type>

B<.kind()> = 'LIST', and has B<$.ofType> with some other
GraphQL::Type.

 my $list-of-strings = GraphQL::List.new(ofType => GraphQLString);

In I<GSL>, Lists are represented by wrapping another type with square
brackets '[' and ']'. e.g.

 [String]

=head4 B<GraphQL::Non-Null> is B<GraphQL::Type>

By default GraphQL types can all take on the value C<null> (in Perl,
C<Nil>).  Wrapping them with Non-Null disallows the C<null>.

B<.kind()> = 'NON_NULL'

 my $non-null-string = GraphQL::Non-Null.new(ofType => GraphQLString);

In I<GSL>, Non-Null types are represented by appending an exclation
point, '!'. e.g.

 String!

To define a Perl class with a non-null attribute, both add the C<:D>
type constraint to the type, and also specify it as C<is required> (or
give it a default).  To mark a type in a method as non-null, append
with an exclamation point. e.g.

 class Something
 {
     has Str:D $.my is rw is required;

     method something(Str :$somearg! --> ID) { ... }
 }

=head4 B<GraphQL::InputValue> is B<GraphQL::Type>

The type is used to represent arguments for B<GraphQL::Field>s and
B<Directive>s arguments as well as the C<inputFields> of a
B<GraphQL::Input>. Has a C<$.type> attribute and optionally
a C<$.defaultValue> attribute.

 my $inputvalue = GraphQL::InputValue.new(name => 'somearg',
                                          type => GraphQLString,
                                          defaultValue => 'some default');

in I<GSL>:

 somearg: String = "some default"

in Perl:

 Str :$somearg = 'some default'

=head4 B<GraphQL::Field> is B<GraphQL::Type> does B<Deprecatable>

In addition to the inherited B<.name>, B<.description>,
B<.isDeprecated>, B<.deprecationReason>, has attributes B<.args> which
is an array of B<GraphQL::InputValue>s, and B<.type> which is the type
of this field.  Since the Field is the place where the Schema connects
to resolvers, there is also a B<.resolver> attribute which can be
connected to arbitrary code.  Much more about resolvers in Resolution
below.

 my $field = GraphQL::Field.new(
    name => 'myfield',
    type => GraphQLString,
    args => GraphQL::InputValue.new(
                name => 'somearg',
                type => GraphQLString,
                defaultValue => 'some default'),
    resolver => sub { ... });

In I<GSL>:

 myfield(somearg: String = "some default"): String

In Perl:

 method myfield(Str :$somearg = 'some default' --> Str) { ... }

Note that as a strongly, staticly typed system, every argument must be
a named argument, and have an attached type (a valid one in the list
above that map to GraphQL types), and the return must specify a type.

You can deprecate by setting the attributes B<.isDeprecated> and
optionally B<.deprecationReason> or using the I<GSL> B<@deprecate>
directive described below.

=head4 B<GraphQL::Interface> is B<GraphQL::Type> does B<HasFields>

In addition to the inherited B<$.name>, B<$.description>, and
B<@.fieldlist>, also has the attribute B<@.possibleTypes> with the
list of object types that implement the interface.  You needn't set
B<@.possibleTypes>, as each B<GraphQL::Object> specifies which
interfaces they implement, and the Schema finalization will list them
all here.

 my $interface = GraphQL::Interface.new(
    name => 'myinterface',
    fieldlist => (GraphQL::Field.new(...), GraphQL::Field.new(...))
 );

In I<GSL>:

 interface myinterface {
   ...fields...
 }

=head4 B<GraphQL::Object> is B<GraphQL::Type> does B<HasFields>

In addition to the inherited B<$.name>, B<$.description>, and
B<@.fieldlist>, also has the attribute B<@.interfaces> with the
interfaces which the object implements, and the B<.kind()> method
which always returns 'OBJECT'.

 my $obj = GraphQL::Object.new(
    name => 'myobject',
    interfaces => ($someinterface, $someotherinterface),
    fieldlist => (GraphQL::Field.new(...), GraphQL::Field.new(...))
 );

In I<GSL>:

 type myobject implements someinterface, someotherinterface {
   ...fields...
 }

In Perl:

 class myobject {
     ...fields...
 }

NOTE: Interfaces aren't yet implemented for the perl classes.

=head4 B<GraphQL::Input> is B<GraphQL::Type>

Input Objects are object like types used as inputs to queries.  Their
B<.kind()> method returns 'INPUT_OBJECT'.  They have a
B<@.inputFields> array of B<GraphQL::InputValue>s, very similar to the
fields defined within a normal Object.

 my $obj = GraphQL::Input.new(
    name => 'myinputobject',
    inputFields => (GraphQL::InputValue.new(...), GraphQL::InputValue.new(...)
 );

In I<GSL>:

 input myinputobject {
    ...inputvalues...
 }

In Perl, you must specify a class explicitly as a GraphQL::InputObject:

 class myinputobject is GraphQL::InputObject {
    ...inputvalues...
 }

=head4 B<GraphQL::Union> is B<GraphQL::Type>

A union has B<.kind()> = 'UNION', and a B<@.possibleTypes> attribute
listing the types of the union.

 my $union = GraphQL::Union.new(
    name => 'myunion',
    possibleTypes => ($someobject, $someotherobject)
 );

In I<GSL>:

 union myunion = someobject | someotherobject

NOTE: Not yet implemented in Perl classes.

=head4 B<GraphQL::Enum> is B<GraphQL::Type>

Has B<.kind()> = 'ENUM', and B<@.enumValues> with a list of
B<GraphQL::EnumValue>s.  The accessor method for B<.enumValues()>
takes an optional I<Bool> argument C<:$includeDeprecated> which will
either include deprecated values or exclude them.

 my $enum = GraphQL::Enum.new(
    name => 'myenum',
    enumValues => (GraphQL::EnumValue.new(...), GraphQL::EnumValue.new(...))
 );

In I<GSL>:

 enum myenum { VAL1 VAL2 ... }

In Perl:

 enum myenum <VAL1 VAL2 ...>;

=head4 B<GraphQL::Directive> is B<GraphQL::Type>

Still needs work...

=end pod

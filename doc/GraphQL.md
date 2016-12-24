GraphQL
=======

SYNOPSIS
--------

    use GraphQL;

    class Query
    {
        method hello(--> Str) { 'Hello World' }
    }

    my $schema = GraphQL::Schema.new(Query);

    say $schema.execute('{ hello }').to-json;

DESCRIPTION
-----------

"GraphQL is a query language for APIs and a runtime for fulfilling those queries with your existing data. GraphQL provides a complete and understandable description of the data in your API, gives clients the power to ask for exactly what they need and nothing more, makes it easier to evolve APIs over time, and enables powerful developer tools." - Facebook Inc., [**http://graphql.org**](**http://graphql.org**).

The GraphQL Language is described in detail at [**http://graphql.org**](**http://graphql.org**) which also includes the draft specification. This module is a Perl 6 server implementation of that specification (or will be once it is complete). The intent of this documentation isn't to fully describe GraphQL and its usage, but rather to describe that Perl implementation and how various functionality is accessible through Perl. This document will assume basic awareness of GraphQL and that standard.

OVERVIEW
--------

GraphQL itself isn't a database, it is the interface between the client and whatever database or other data store you use. Constructing a GraphQL server consists of describing your API **Schema** consisting of a data structure of data **Types**, and connecting to subroutines or methods for **Resolution** of the actual data values. The **Schema** is the controller or orchestrator for everything. It performs two major functions, **Validation** to determine if a query is valid at all, and **Execution**, which makes calls to arbitrary code for **Resolution** to determine the resulting data structure. The GraphQL language also specifies **Introspection** which is essentially **Resolution** carried out by the Schema itself to describe itself.

The synopsis above describes the simplest GraphQL server possible. It consists of a single Type or Class called **Query**, with a single field in it called *hello* of type String, with a method attached to it that returns the string `Hello World`.

The schema is constructed by passing the Perl 6 class into the `GraphQL::Schema`'s `new()` constructor. The example then passes in the simplest GraphQL query {hello}. Execution will call the `hello()` method and return the result in a `GraphQL::Result` structure that can then be converted into JSON with `to-json()` method which will return the result:

    {
      "data": {
        "hello": "Hello World"
      }
    }

In a typical GraphQL Web server, the query would be HTTP POSTed to an endpoint at `/graphql` which would call `GraphQL::Schema.execute()` and send the resulting JSON string back to the requester.

Each of those steps will be described in more detail below.

Schema Styles
-------------

This module currently supports three different *styles* for expressing GraphQL types for your GraphQL schema:

  * **Manual** - You can construct each type by creating and nesting various `GraphQL::*` objects. 

For the "Hello World" example, it would look like this:

    my $schema = GraphQL::Schema.new(
        GraphQL::Object.new(
            name => 'Query',
            fieldlist => GraphQL::Field.new(
                name => 'hello',
                type => $GraphQLString,
                resolver => sub { 'Hello World' }
            )
        )
    );

  * **GraphQL Schema Language** or **GSL**- The Perl 6 GraphQL engine includes a complete parser for the *GraphQL Schema Language* described in detail at [**http://graphql.org**](**http://graphql.org**). It is important to note that this is a _different_ language from the *GraphQL Query language* which will be described later. There is also a handy cheat sheet for the *GSL* at [https://github.com/sogko/graphql-shorthand-notation-cheat-sheet/](https://github.com/sogko/graphql-shorthand-notation-cheat-sheet/).

For the "Hello World" example, it would look like this:

    my $schema = GraphQL::Schema.new('type Query { hello: String }',
        resolvers => { Query => { hello => sub { 'Hello World' } } });

Note that while the schema type descriptions are provided in the *GSL*, the resolving functions for each field must be separately supplied in a two level hash with the names of each Object Type at the first level, and Field at the second level.

  * **Direct Perl Classes** - You can also simply pass in Perl 6 classes directly. A matching schema is constructed by examining the classes with the Perl language Metamodel for introspection. Given the GraphQL type restrictions, not everything you can express in Perl will result in a valid Schema, so it is important to use only the types as described below. Also restrict the names of attributes and methods to the alpha-numeric and '_'. (No fancy unicode names, or kebab-case names.)

For the "Hello World" example, it looks like this:

    class Query
    {
        method hello(--> Str) { 'Hello World' }
    }

    my $schema = GraphQL::Schema.new(Query);

Under the hood, the Schemas all look the same, regardless of which style you use to construct them. The later two options are just additional syntactic sugar to make things easier. You can also mix and match, making some types one way and some another and everything will still work fine.

Types
-----

GraphQL is a strongly, staticly typed language. Every type must be defined precisely up front, and all can be checked during validation phase prior to execution.

The Perl Class hierarchy for GraphQL Types includes these:

  * **GraphQL::Type** (abstract, not to be used directly, only inherited

  * **GraphQL::Scalar**

  * **GraphQL::String**

  * **GraphQL::Int**

  * **GraphQL::Float**

  * **GraphQL::ID**

  * **GraphQL::EnumValue**

  * **GraphQL::List**

  * **GraphQL::Non-Null**

  * **GraphQL::InputValue**

  * **GraphQL::Field**

  * **GraphQL::Interface**

  * **GraphQL::Object**

  * **GraphQL::InputObjectType**

  * **GraphQL::Union**

  * **GraphQL::Enum**

  * **GraphQL::Directive**

### *role* **Deprecatable**

**GraphQL::Field** and **GraphQL::EnumValue** are **Deprecatable**

They get two extra public attributes `$.isDeprecated` *Bool*, default `False`, and `$.deprecationReason` *Str*.

They also get the method `.deprecate(Str $reason)`, which defaults to "No longer supported."

In *GSL*, you can also deprecate with the directive **@deprecate** or `@deprecate(reason: "something")`. More on directives below.

### *role* **HasFields**

**GraphQL::Object** and **GraphQL::Interface** both include a role **HasFields** that give them a **@.fieldlist** array of **GraphQL::Field**s, a method **.field($name)** to look up a field, and a method **.fields(Bool :$includeDeprecated)** that will return the list of fields. Meta-fields with names starting with "__" are explicitly not returned in the `.fields()` list, but can be requested with `.field()`.

### **GraphQL::Type**

This is the main GraphQL type base class. It has public attributes `$.name` and `$.description`. It isn't intended to be used directly, it is just the base class for all the other Types.

The description field can be explicitly assigned in the creation of each GraphQL::Type.

In *GSL*, you can set the description field by preceding the definition of types with comments:

    # Description for mytype
    type mytype {
      # Description for myfield
      myfield: Str
    }

In Perl, the description field is set from the Meto-Object Protocol $obj.WHY method which by default will be set automatically with Pod declarations. e.g.

    #| Description for mytype
    class mytype {
      #| Description for myfield
      has Str $.myfield
    }

### **GraphQL::Scalar** is **GraphQL::Type**

Serves as the base class for scalar, leaf types. It adds the method **.kind()** = 'SCALAR';

There are several core GraphQL scalar types that map to Perl basic scalar types:

<table>
  <thead>
    <tr>
      <td>GraphQL Type</td>
      <td>Perl Type Class</td>
      <td>Perl Object Instance</td>
      <td>Perl Type</td>
    </tr>
  </thead>
  <tr>
    <td>String</td>
    <td>GraphQL::String</td>
    <td>$GraphQLString</td>
    <td>Str</td>
  </tr>
  <tr>
    <td>Int</td>
    <td>GraphQL::Int</td>
    <td>$GraphQLInt</td>
    <td>Int</td>
  </tr>
  <tr>
    <td>Float</td>
    <td>GraphQL::Float</td>
    <td>$GraphQLFloat</td>
    <td>Num</td>
  </tr>
  <tr>
    <td>Boolean</td>
    <td>GraphQL::Boolean</td>
    <td>$GraphQLBoolean</td>
    <td>Bool</td>
  </tr>
  <tr>
    <td>ID</td>
    <td>GraphQL::ID</td>
    <td>$GraphQLID</td>
    <td>ID (subset of Cool)</td>
  </tr>
</table>

The Perl Object Instances are just short hand pre-created objects that can be used since those types are needed so frequently.

For example, GraphQL::String.new creates a String type, but you can just use $GraphQLString which is already made.

You can create your own additional scalar types as needed:

    my $URL = GraphQL::Scalar.new(name => 'URL');

or in *GSL*:

    scalar URL

#### **GraphQL::String** is **GraphQL::Scalar**

Core String type, maps to Perl type `Str`.

You can create your own:

    my $String = GraphQL::String.new;

or just use `$GraphQLString`.

#### **GraphQL::Int** is **GraphQL::Scalar**

Core Int type, maps to Perl type `Int`.

You can create your own:

    my $Int = GraphQL::Int.new;

or just use `$GraphQLInt`.

#### **GraphQL::Float** is **GraphQL::Scalar**

Core Float type, maps to Perl type `Num`.

You can create your own:

    my $Float = GraphQL::Float.new;

or just use `$GraphQLFloat`.

#### **GraphQL::Boolean** is **GraphQL::Scalar**

Core Boolean type, maps to Perl type `Bool`.

You can create your own:

    my $Boolean = GraphQL::Boolean.new;

or just use `$GraphQLBoolean`.

#### **GraphQL::ID** is **GraphQL::Scalar**

Core ID type, maps to Perl type `ID` which is a subset of `Cool`.

You can create your own:

    my $ID = GraphQL::ID.new;

or just use `$GraphQLID`.

#### **GraphQL::EnumValue** is **GraphQL::Scalar** does **Deprecatable**

The individual enumerated values of an `Enum`, represented as quoted strings in JSON.

    my $enumvalue = GraphQL::EnumValue.new(name => 'SOME_VALUE');

They can also be deprecated:

    my $enumvalue = GraphQL::EnumValue.new(name => 'SOME_VALUE',
                                           :isDeprecated,
                                           reason => 'Just because');

or can be later deprecated:

    $enumvalue.deprecate('Just because');

See **GraphQL::Enum** for more information about creating EnumValues.

#### **GraphQL::List** is **GraphQL::Type**

**.kind()** = 'LIST', and has **$.ofType** with some other GraphQL::Type.

    my $list-of-strings = GraphQL::List.new(ofType => $GraphQLString);

In *GSL*, Lists are represented by wrapping another type with square brackets '[' and ']'. e.g.

    [String]

#### **GraphQL::Non-Null** is **GraphQL::Type**

By default GraphQL types can all take on the value `null` (in Perl, `Nil`). Wrapping them with Non-Null disallows the `null`.

**.kind()** = 'NON_NULL'

    my $non-null-string = GraphQL::Non-Null.new(ofType => $GraphQLString);

In *GSL*, Non-Null types are represented by appending an exclation point, '!'. e.g.

    String!

To define a Perl class with a non-null attribute, both add the `:D` type constraint to the type, and also specify it as `is required` (or give it a default). To mark a type in a method as non-null, append with an exclamation point. e.g.

    class Something
    {
        has Str:D $.my is rw is required;

        method something(Str :$somearg! --> ID) { ... }
    }

#### **GraphQL::InputValue** is **GraphQL::Type**

The type is used to represent arguments for **GraphQL::Field**s and **Directive**s arguments as well as the `inputFields` of a **GraphQL::InputObjectType**. Has a `$.type` attribute and optionally a `$.defaultValue` attribute.

    my $inputvalue = GraphQL::InputValue.new(name => 'somearg',
                                             type => $GraphQLString,
                                             defaultValue => 'some default');

in *GSL*:

    somearg: String = "some default"

in Perl:

    Str :$somearg = 'some default'

#### **GraphQL::Field** is **GraphQL::Type** does **Deprecatable**

In addition to the inherited **.name**, **.description**, **.isDeprecated**, **.deprecationReason**, has attributes **.args** which is an array of **GraphQL::InputValue**s, and **.type** which is the type of this field. Since the Field is the place where the Schema connects to resolvers, there is also a **.resolver** attribute which can be connected to arbitrary code. Much more about resolvers in Resolution below.

    my $field = GraphQL::Field.new(
       name => 'myfield',
       type => $GraphQLString,
       args => GraphQL::InputValue.new(
                   name => 'somearg',
                   type => $GraphQLString,
                   defaultValue => 'some default'),
       resolver => sub { ... });

In *GSL*:

    myfield(somearg: String = "some default"): String

In Perl:

    method myfield(Str :$somearg = 'some default' --> Str) { ... }

Note that as a strongly, staticly typed system, every argument must be a named argument, and have an attached type (a valid one in the list above that map to GraphQL types), and the return must specify a type.

You can deprecate by setting the attributes **.isDeprecated** and optionally **.deprecationReason** or using the *GSL* **@deprecate** directive described below.

#### **GraphQL::Interface** is **GraphQL::Type** does **HasFields**

In addition to the inherited **$.name**, **$.description**, and **@.fieldlist**, also has the attribute **@.possibleTypes** with the list of object types that implement the interface. You needn't set **@.possibleTypes**, as each **GraphQL::Object** specifies which interfaces they implement, and the Schema finalization will list them all here.

    my $interface = GraphQL::Interface.new(
       name => 'myinterface',
       fieldlist => (GraphQL::Field.new(...), GraphQL::Field.new(...))
    );

In *GSL*:

    interface myinterface {
      ...fields...
    }

#### **GraphQL::Object** is **GraphQL::Type** does **HasFields**

In addition to the inherited **$.name**, **$.description**, and **@.fieldlist**, also has the attribute **@.interfaces** with the interfaces which the object implements, and the **.kind()** method which always returns 'OBJECT'.

    my $obj = GraphQL::Object.new(
       name => 'myobject',
       interfaces => ($someinterface, $someotherinterface),
       fieldlist => (GraphQL::Field.new(...), GraphQL::Field.new(...))
    );

In *GSL*:

    type myobject implements someinterface, someotherinterface {
      ...fields...
    }

In Perl:

    class myobject {
        ...fields...
    }

NOTE: Interfaces aren't yet implemented for the perl classes.

#### **GraphQL::InputObjectType** is **GraphQL::Type**

Input Objects are object like types used as inputs to queries. Their **.kind()** method returns 'INPUT_OBJECT'. They have a **@.inputFields** array of **GraphQL::InputValue**s, very similar to the fields defined within a normal Object.

    my $obj = GraphQL::InputObjectType.new(
       name => 'myinputobject',
       inputFields => (GraphQL::InputValue.new(...), GraphQL::InputValue.new(...)
    );

In *GSL*:

    input myinputobject {
       ...inputvalues...
    }

In Perl, you must specify a class explicitly as a GraphQL::InputObject:

    class myinputobject is GraphQL::InputObject {
       ...inputvalues...
    }

#### **GraphQL::Union** is **GraphQL::Type**

A union has **.kind()** = 'UNION', and a **@.possibleTypes** attribute listing the types of the union.

    my $union = GraphQL::Union.new(
       name => 'myunion',
       possibleTypes => ($someobject, $someotherobject)
    );

In *GSL*:

    union myunion = someobject | someotherobject

NOTE: Not yet implemented in Perl classes.

#### **GraphQL::Enum** is **GraphQL::Type**

Has **.kind()** = 'ENUM', and **@.enumValues** with a list of **GraphQL::EnumValue**s. The accessor method for **.enumValues()** takes an optional *Bool* argument `:$includeDeprecated` which will either include deprecated values or exclude them.

    my $enum = GraphQL::Enum.new(
       name => 'myenum',
       enumValues => (GraphQL::EnumValue.new(...), GraphQL::EnumValue.new(...))
    );

In *GSL*:

    enum myenum { VAL1 VAL2 ... }

In Perl:

    enum myenum <VAL1 VAL2 ...>;

#### **GraphQL::Directive** is **GraphQL::Type**

Still needs work...

use v6;
use GraphQL;
use GraphQL::Actions;
use GraphQL::Types;
use Test;

my $schema = GraphQL::Schema.new;

my $actions = GraphQL::Actions.new(:$schema);

is GraphQL::Grammar.parse('testname', :$actions, rule => 'Name').made,
    'testname', 'Name';

is GraphQL::Grammar.parse('27', :$actions, rule => 'Value').made,
    27, 'Int Value';

is GraphQL::Grammar.parse('-27', :$actions, rule => 'Value').made,
    -27, 'Negative Int Value';

is GraphQL::Grammar.parse('27.47', :$actions, rule => 'Value').made,
    27.47, 'Float Value';

is GraphQL::Grammar.parse('-27.47', :$actions, rule => 'Value').made,
    -27.47, 'Negative Float Value';

is GraphQL::Grammar.parse('27e47', :$actions, rule => 'Value').made,
    27e47, 'Exp Float Value';

is GraphQL::Grammar.parse('"foo"', :$actions, rule => 'Value').made,
    'foo', 'String Value';

is GraphQL::Grammar.parse('"f\"oo"', :$actions, rule => 'Value').made,
    'f"oo', 'String Value, escaped "';

is GraphQL::Grammar.parse('"☺"', :$actions, rule => 'Value').made,
    '☺', 'Unicode String Value';

is GraphQL::Grammar.parse('"this \u263a is fun!"',
                          :$actions, rule => 'Value').made,
    'this ☺ is fun!', 'Unicode String Value';

is GraphQL::Grammar.parse('true', :$actions, rule => 'Value').made,
    True, 'Boolean True';

is GraphQL::Grammar.parse('false', :$actions, rule => 'Value').made,
    False, 'Boolean False';

is GraphQL::Grammar.parse('null', :$actions, rule => 'Value').made,
    Nil, 'null';

is-deeply GraphQL::Grammar.parse('$var', :$actions, rule => 'Value').made,
    GraphQL::Variable.new(name => 'var'), 'Variable';

is-deeply GraphQL::Grammar.parse('interface Entity { id: ID! name: String }',
                                 :$actions, rule => 'Interface').made,
    GraphQL::Interface.new(
        name => 'Entity',
        fieldlist => (
            GraphQL::Field.new(
                name => 'id',
                type => GraphQL::Non-Null.new(ofType => GraphQLID),
            ),
            GraphQL::Field.new(
                name => 'name',
                type => GraphQLString
            )
        )
    ), 'Interface';

is-deeply GraphQL::Grammar.parse('scalar Url',
                                 :$actions, rule => 'Scalar').made,
    GraphQL::Scalar.new(name => 'Url'), 'Scalar';

is-deeply GraphQL::Grammar.parse('enum USER_STATE { NOT_FOUND ACTIVE
                                                    INACTIVE SUSPENDED }',
                                 :$actions, rule => 'Enum').made,
  GraphQL::Enum.new(name => 'USER_STATE',
                    enumValues => [
                        GraphQL::EnumValue.new(name => 'NOT_FOUND'),
                        GraphQL::EnumValue.new(name => 'ACTIVE'),
                        GraphQL::EnumValue.new(name => 'INACTIVE'),
                        GraphQL::EnumValue.new(name => 'SUSPENDED')]),
    'Enum';

done-testing;

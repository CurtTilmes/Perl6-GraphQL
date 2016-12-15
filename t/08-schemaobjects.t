use v6;
use GraphQL;
use GraphQL::Actions;

use Test;

my $actions = GraphQL::Actions.new;

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


done-testing;

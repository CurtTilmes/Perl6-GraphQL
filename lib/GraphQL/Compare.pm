unit module GraphQL::Compare;

use GraphQL::Types;

CORE::<&infix:<eqv>>.add_dispatchee(
multi infix:<eqv>(GraphQL::Field $l, GraphQL::Field $r --> Bool)
{
    $l.name eqv $r.name and
    $l.description eqv $r.description and
    $l.type eqv $r.type;
});

CORE::<&infix:<eqv>>.add_dispatchee(
multi infix:<eqv>(GraphQL::Interface $l, GraphQL::Interface $r --> Bool)
{
    $l.name eqv $r.name and
    $l.description eqv $r.description and
    $l.fieldlist eqv $r.fieldlist and
    $l.possibleTypes».name eqv $r.possibleTypes».name;
});

CORE::<&infix:<eqv>>.add_dispatchee(
multi infix:<eqv>(GraphQL::Object $l, GraphQL::Object $r --> Bool)
{
    $l.name eqv $r.name and
    $l.description eqv $r.description and
    $l.fieldlist eqv $r.fieldlist and
    $l.interfaces».name eqv $r.interfaces».name;
});

CORE::<&infix:<eqv>>.add_dispatchee(
multi infix:<eqv>(GraphQL::Union $l, GraphQL::Union $r --> Bool)
{
    $l.name eqv $r.name and
    $l.description eqv $r.description and
    $l.possibleTypes».name eqv $r.possibleTypes».name;
});

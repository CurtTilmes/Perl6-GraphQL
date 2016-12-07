use GraphQL::Types;

unit class GraphQL::Actions;
#
# There are two "top level" rules, <Document> for a GraphQL query document,
# and <TypeSchema> for a GraphQL type schema.
#

#
# Only for <TypeSchema>, as fields and lists are defined, keep track
# of any that refer to types, then after all the types are defined,
# loop through them, linking to the created types.  This allows, for
# example, a field of an Object to refer to another Object of the same
# type.
#
has @!fields-to-type;  # These types have a single type
# 'typename' => GraphQL::Field or GraphQL::InputValue (set $.type)
#            or GraphQL::Non-Null or GraphQL::List    (set $.ofType)

has @!lists-to-type;   # These take lists of types
# ('list', 'of', 'typenames') => GraphQL::Object (@.interfaces)
#                             or GraphQL::Union  (@.possibleTypes)

#
# Returns this (in .made) when making a <Document>
#
has GraphQL::Document $!q = GraphQL::Document.new;

#
# Returns this (in .made) when making a <TypeSchema>
#
has GraphQL::Schema $!s = GraphQL::Schema.new;

method Document($/)
{
    if $!q.operations{''} and $!q.operations.elems() != 1
    {
        die "This anonymous operation must be the only defined operation";
    }

    make $!q;
}

method OperationDefinition($/)
{
    my $name = $<Name> ?? $<Name>.made !! '';

    die "Duplicate definition of $name" if $!q.operations{$name}.defined;

    $!q.operations{$name} = GraphQL::Operation.new(
        name         => $name,
        operation    => $<OperationType> ?? $<OperationType>.Str !! 'query',
        selectionset => $<SelectionSet>.made
    );
}

method SelectionSet($/)
{
    make $<Selection>».made
}

method Selection($/)
{
    make $<Field>.made // $<FragmentSpread>.made // $<InlineFragment>.made;
}

method Field($/)
{
    make GraphQL::QueryField.new(
        alias => $<Alias>.made,
        name => $<Name>.made,
        args => $<Arguments>.made // (),
        directives => $<Directives>.made // (),
        selectionset => $<SelectionSet>.made // ()
    );

}

method Alias($/)
{
    make $<Name>.made;
}

method Arguments($/)
{
    my %args;
    for $<Argument> -> $arg
    {
        %args{$arg<Name>.made} = $arg<Value>.made;
    }
    make %args;
}

method FragmentSpread($/)
{
    make GraphQL::FragmentSpread.new(
        name => $<FragmentName>.made,
        directives => $<Directives>.made
    );
}

method InlineFragment($/)
{
}

method FragmentDefinition($/)
{
    $!q.fragments{$<FragmentName>.made} = GraphQL::Fragment.new(
        name         => $<FragmentName>.made,
        onType       => $<TypeCondition>.made,
        directives   => $<Directives>.made,
        selectionset => $<SelectionSet>.made
    );
}

method FragmentName($/)
{
    make $<Name>.Str;
}

method TypeCondition($/)
{
    make $<NamedType>.made;
}

method Name($/)
{
    make $/.Str;
}

method Value:sym<FloatValue>($/)
{
    make $/.Num;
}

method Value:sym<IntValue>($/)
{
    make $/.Int;
}

method StringValue($/)
{
    make $<InsideString>.Str;
}

method Value:sym<StringValue>($/)
{
    make $<StringValue>.made;
}

method Value:sym<BooleanValue>($/)
{
    make $/.Str eq 'true' ?? True !! False;
}

method Value:sym<NullValue>($/)
{
    make 'null'
}

method Type($/)
{
    make $<NonNullType>.made // $<NamedType>.made // $<ListType>.made;
}

method NamedType($/)
{
    make $<Name>.Str;
}

method ListType($/)
{
    if $<Type>.made ~~ Str
    {
        my $l = GraphQL::List.new();
        push @!fields-to-type, $<Type>.made => $l;
        make $l;
    }
    else
    {
        make GraphQL::List.new(ofType => $<Type>.made);
    }
}

method NonNullType($/)
{
    my $type = $<NamedType>.made || $<ListType>.made;

    if $type ~~ Str
    {
        my $n = GraphQL::Non-Null.new();
        push @!fields-to-type, $type => $n;
        make $n;
    }
    else
    {
        make GraphQL::Non-Null.new(ofType => $type);
    }
}

method InterfaceDefinition($/)
{
    make $!s.addtype(GraphQL::Interface.new(name => $<Name>.made,
                         fields => $<FieldDefinitionList>.made));
}

method FieldDefinitionList($/)
{
    my $fieldlist = GraphQL::FieldList.new;

    for $<FieldDefinition> -> $field
    {
        $fieldlist{$field.made.name} = $field.made
    }

    make $fieldlist;
}

method FieldDefinition($/)
{
    if $<Type>.made ~~ Str
    {
        my $f = GraphQL::Field.new(
            name => $<Name>.made,
            args => $<ArgumentDefinitions>.made // (),
        );
        push @!fields-to-type, $<Type>.made => $f;
        make $f;
    }
    else
    {
        make GraphQL::Field.new(
            name => $<Name>.made,
            type => $<Type>.made,
            args => $<ArgumentDefinitions>.made // (),
        );
    }
}

method ObjectTypeDefinition($/)
{
#    say '-' x 70;
#    say "Making Object";
#    say $/;
    
    my $o = GraphQL::Object.new(name => $<Name>.made,
                                fields => $<FieldDefinitionList>.made);

    $!s.addtype($o);

    if $<ImplementsDefinition>.made
    {
        push @!lists-to-type, 
             ($<ImplementsDefinition>.made => $o);
    }
}

method ImplementsDefinition($/)
{
    make $<Name>».made;
}

method UnionDefinition($/)
{
    my $u = GraphQL::Union.new(name => $<Name>.made);

    $!s.addtype($u);

    push @!lists-to-type, ($<UnionList>.made => $u);
}

method UnionList($/)
{
    make $<Name>».made; 
}

method EnumDefinition($/)
{
    $!s.addtype(GraphQL::Enum.new(name => $<Name>.made,
				  enumValues => $<EnumValues>.made));
}

method EnumValues($/)
{
    make $<Name>.map({ GraphQL::EnumValue.new(name => $_.made) });
}

method DefaultValue($/)
{
    make $<Value>.made;
}

method ArgumentDefinition($/)
{
    my $t = GraphQL::InputValue.new(name => $<Name>.made,
                                    defaultValue => $<DefaultValue>.made);

    push @!fields-to-type, $<Type>.made => $t;

    make $t;
}

method ArgumentDefinitions($/)
{
    make $<ArgumentDefinition>».made;
}

method ScalarDefinition($/)
{
    $!s.addtype(GraphQL::Scalar.new(name => $<Name>.made));
}

method TypeSchema($/)
{
    #
    # Go through all the saved @fields-to-type and @lists-to-type, look
    # them up in the schema type list, and patch them to the right type
    # now that they are all defined
    #
    for @!fields-to-type -> $field
    {
        die "Haven't defined $field.key()" unless $!s.type($field.key);

        given $field.value
        {
            when GraphQL::Field | GraphQL::InputValue
            {
                $field.value.type = $!s.type($field.key);
            }

            when GraphQL::Non-Null | GraphQL::List
            {
                $field.value.ofType = $!s.type($field.key);
            }
        }
    }

    for @!lists-to-type -> $typelist
    {
        my @list-of-types;
        for $typelist.key -> $name
        {
            die "Haven't defined interface $name" unless $!s.type($name);
            push @list-of-types, $!s.type($name);
        }
        
        given $typelist.value
        {
            when GraphQL::Object
            { 
                $typelist.value.interfaces = @list-of-types
            }
            when GraphQL::Union
            {
                $typelist.value.possibleTypes = @list-of-types;
            }
        }
    }

    make $!s;
}

method SchemaDefinition($/)
{
    $!s.query = $<SchemaQuery>.made;
}

method SchemaQuery($/)
{
    make $<Name>.made;
}

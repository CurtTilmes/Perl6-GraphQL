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
# Supply an existing schema to just add more types to it
#
has GraphQL::Schema $.schema = GraphQL::Schema.new;

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
        vars         => $<VariableDefinitions>.made // (),
        selectionset => $<SelectionSet>.made
    );
}

method VariableDefinitions($/)
{
    make $<VariableDefinition>».made;
}

method VariableDefinition($/)
{
    die "Unknown type $<Type>.made" unless $!schema.type($<Type>.made);

    make GraphQL::Variable.new(
        name => $<Variable>.<Name>.made,
        type => $!schema.type($<Type>.made),
        defaultValue => $<DefaultValue>.made
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
    make GraphQL::InlineFragment.new(
        onType => $<TypeCondition>.made,
        directives => $<Directives>.made,
        selectionset => $<SelectionSet>.made
    );
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

method Variable($/)
{
    make GraphQL::Variable.new(name => $<Name>.made);
}

method Value:sym<Variable>($/)
{
    make $<Variable>.made;
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
    my $i = GraphQL::Interface.new(name => $<Name>.made,
                         fields => $<FieldDefinitionList>.made);

    $i.add-comment-description($/);

    $!schema.addtype($i);
}

method FieldDefinitionList($/)
{
    make $<FieldDefinition>».made;

}

method Comment($/)
{
    make $/.Str.subst(/^\#\s?/, '');
}

method FieldDefinition($/)
{
    my $f = GraphQL::Field.new(
	name => $<Name>.made,
	args => $<ArgumentDefinitions>.made // (),
    );

    $f.add-comment-description($/);

    if $<Type>.made ~~ Str
    {
        push @!fields-to-type, $<Type>.made => $f;
    }
    else
    {
	$f.type = $<Type>.made;
    }

    if $<Directives>.made<deprecated>:exists
    {
	if $<Directives>.made<deprecated><reason>:exists
	{
	    $f.deprecate($<Directives>.made<deprecated><reason>);
	}
	else
	{
	    $f.deprecate();
	}
    }

    make $f;
}

method ObjectTypeDefinition($/)
{
    my $o = GraphQL::Object.new(name => $<Name>.made,
                                fields => $<FieldDefinitionList>.made);

    $o.add-comment-description($/);

    $!schema.addtype($o);

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

    $u.add-comment-description($/);

    $!schema.addtype($u);

    push @!lists-to-type, ($<UnionList>.made => $u);
}

method UnionList($/)
{
    make $<Name>».made; 
}

method EnumDefinition($/)
{
    my $e = GraphQL::Enum.new(name => $<Name>.made,
                              enumValues => $<EnumValues>.made);

    $e.add-comment-description($/);


    $!schema.addtype($e);
}

method EnumValues($/)
{
    make $<EnumValue>».made;
}

method EnumValue($/)
{
    my $enumvalue = GraphQL::EnumValue.new(name => $<Name>.made);

    $enumvalue.add-comment-description($/);

    if $<Directives>.made<deprecated>:exists
    {
	if $<Directives>.made<deprecated><reason>:exists
	{
	    $enumvalue.deprecate($<Directives>.made<deprecated><reason>);
	}
	else
	{
	    $enumvalue.deprecate();
	}
    }
    make $enumvalue;
}

method Directives($/)
{
    my %directives;
    for $<Directive> -> $directive
    {
	%directives{$directive<Name>.made} = $directive<Arguments>.made // Nil;
    }
    make %directives;
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
    my $o = GraphQL::Scalar.new(name => $<Name>.made);

    $o.add-comment-description($/);

    $!schema.addtype($o);
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
        die "Haven't defined $field.key()" unless $!schema.type($field.key);

        given $field.value
        {
            when GraphQL::Field | GraphQL::InputValue
            {
                $field.value.type = $!schema.type($field.key);
            }

            when GraphQL::Non-Null | GraphQL::List
            {
                $field.value.ofType = $!schema.type($field.key);
            }

            default { die "Need to type $field.value.WHAT()" }
        }
    }

    for @!lists-to-type -> $typelist
    {
        my @list-of-types;
        for $typelist.key -> $name
        {
            die "Haven't defined interface $name" unless $!schema.type($name);
            push @list-of-types, $!schema.type($name);
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

            default { die "Need to type $typelist.value.WHAT()" }
        }
    }

    make $!schema;
}

method SchemaDefinition($/)
{
    $!schema.query = $<SchemaQuery>.made;
}

method SchemaQuery($/)
{
    make $<Name>.made;
}

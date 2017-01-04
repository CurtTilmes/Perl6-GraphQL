use GraphQL::Types;

unit class GraphQL::Actions;
#
# There are two "top level" rules, <Document> for a GraphQL query document,
# and <TypeSchema> for a GraphQL type schema.
#

has GraphQL::Document $!q = GraphQL::Document.new;

has $.schema;
has GraphQL::Type @!newtypes;

my %ESCAPE = (
    '"'  => '"',
    '\\' => '\\',
    '/'  => '/',
    'b'  => "\b",
    'f'  => "\f",
    'n'  => "\n",
    'r'  => "\r",
    't'  => "\t"
);

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
    make GraphQL::Variable.new(
        name => $<Variable>.<Name>.made,
        type => $<Type>.made,
        defaultValue => $<DefaultValue>.made
    );
}

method SelectionSet($/)
{
    make $<Selection>».made
}

method Selection($/)
{
    make $<QueryField>.made // $<FragmentSpread>.made // $<InlineFragment>.made;
}

method QueryField($/)
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
        directives => $<Directives>.made // ()
    );
}

method InlineFragment($/)
{
    make GraphQL::InlineFragment.new(
        onType => $<TypeCondition>.made,
        directives => $<Directives>.made // (),
        selectionset => $<SelectionSet>.made
    );
}

method FragmentDefinition($/)
{
    $!q.fragments{$<FragmentName>.made} = GraphQL::Fragment.new(
        name         => $<FragmentName>.made,
        onType       => $<TypeCondition>.made,
        directives   => $<Directives>.made // (),
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
    make $<str>».made.join;
}

method str($/)
{
    make ~$/;
}

# copied string escape from JSON::Tiny

my %h = '\\' => "\\",
        '/'  => "/",
        'b'  => "\b",
        'n'  => "\n",
        't'  => "\t",
        'f'  => "\f",
        'r'  => "\r",
        '"'  => "\"";

method str_escape($/)
{
    if $<utf16_codepoint>
    {
        make utf16.new( $<utf16_codepoint>.map({:16(~$_)}) ).decode();
    }
    else
    {
        make %h{~$/};
    }
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
    make Nil
}

method Value:sym<EnumValue>($/)
{
    make $<Name>.made;
}

method ObjectValue($/)
{
    make %( $<ObjectField>».made );
}

method ObjectField($/)
{
    make $<Name>.made => $<Value>.made;
}

method Value:sym<ObjectValue>($/)
{
    make $<ObjectValue>.made;
}

method Type($/)
{
    make $<NonNullType>.made // $<NamedType>.made // $<ListType>.made;
}

method NamedType($/)
{
    make $!schema.type($<Name>.Str);
}

method ListType($/)
{
    make GraphQL::List.new(ofType => $<Type>.made);
}

method NonNullType($/)
{
    my $type = $<NamedType>.made || $<ListType>.made;

    make GraphQL::Non-Null.new(ofType => $type);
}

method Interface($/)
{
    my $i = GraphQL::Interface.new(name => $<Name>.made,
                         fieldlist => $<FieldList>.made);

    $i.add-comment-description($/);

    push @!newtypes, $i;
    make $i;
}

method FieldList($/)
{
    make $<Field>».made;
}

method Comment($/)
{
    make $/.Str.subst(/^\#\s?/, '');
}

method Field($/)
{
    my $f = GraphQL::Field.new(
	name => $<Name>.made,
	args => $<ArgumentDefinitions>.made // (),
        type => $<Type>.made
    );

    $f.add-comment-description($/);

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

method ObjectType($/)
{
    my $o = GraphQL::Object.new(name => $<Name>.made,
                                fieldlist => $<FieldList>.made,
                                interfaces => $<Implements>.made // ());

    $o.add-comment-description($/);

    push @!newtypes, $o;
    make $o;
}

method Implements($/)
{
    make $<Name>.map({ $!schema.type(.made) });
}

method Union($/)
{
    my $u = GraphQL::Union.new(name => $<Name>.made,
                               possibleTypes => $<UnionList>.made);

    $u.add-comment-description($/);

    push @!newtypes, $u;
    make $u;
}

method UnionList($/)
{
    make $<Name>.map({ $!schema.type(.made) });
}

method Enum($/)
{
    my $e = GraphQL::Enum.new(name => $<Name>.made,
                              enumValues => $<EnumValues>.made);

    $e.add-comment-description($/);

    push @!newtypes, $e;
    make $e;
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
	%directives{$directive<Name>.made} = $directive<Arguments>.made // ();
    }
    make %directives;
}

method DefaultValue($/)
{
    make $<Value>.made;
}

method ArgumentDefinition($/)
{
    make GraphQL::InputValue.new(name => $<Name>.made,
                                 type => $<Type>.made,
                                 defaultValue => $<DefaultValue>.made);
}

method ArgumentDefinitions($/)
{
    make $<ArgumentDefinition>».made;
}

method Scalar($/)
{
    my $o = GraphQL::Scalar.new(name => $<Name>.made);

    $o.add-comment-description($/);

    push @!newtypes, $o;
    make $o;
}

method InputObject($/)
{
    my $o = GraphQL::Input.new(name => $<Name>.made,
                               inputFields => $<InputFieldList>.made);

    $o.add-comment-description($/);

    push @!newtypes, $o;
    make $o;
}

method InputFieldList($/)
{
    make $<InputField>».made;
}

method InputField($/)
{
    my $f = GraphQL::InputValue.new(name => $<Name>.made,
                                    type => $<Type>.made,
                                    defaultValue => $<DefaultValue>.made);

    $f.add-comment-description($/);

    make $f;
}

method TypeSchema($/)
{
    $!schema.add-type(@!newtypes);

    make $!schema;
}

method Schema($/)
{
    $!schema.query = $<SchemaQuery>.made;
    $!schema.mutation = $<SchemaMutation>.made;
}

method SchemaQuery($/)
{
    make $<Name>.made;
}

method SchemaMutation($/)
{
    make $<Name>.made;
}

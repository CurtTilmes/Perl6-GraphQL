unit module GraphQL::Validation;

use GraphQL::Types;

sub ValidateDocument(:$document, :$schema --> Bool) is export
{
    for $document.operations.values -> $operation
    {
        validate-operation(:$document, :$schema, :$operation);
    }

    for $document.fragments.values -> $fragment
    {
        validate-selectionset(:$document, :$schema,
                              type => $fragment.onType,
                              selectionset => $fragment.selectionset);
    }
    return True;
}

sub validate-operation(:$document, :$schema, :$operation)
{
    my $type = $operation.operation eq 'mutation'
                     ?? $schema.mutationType
                     !! $schema.queryType;

    my @selectionset = $operation.selectionset;

    validate-selectionset(:$document, :$schema, :$type, :@selectionset);
}

sub validate-selectionset(:$document, :$schema, :$type, :@selectionset)
{
    if $type ~~ GraphQL::Union
    {
        for $type.possibleTypes -> $type
        {
            validate-selectionset(:$document, :$schema, :$type, :@selectionset);
        }
        return True;
    }

    for @selectionset
    {
        when GraphQL::InlineFragment
        {
            if $type.fragment-applies(.onType)
            {
                validate-selectionset(:$document, :$schema, :$type,
                                      selectionset => .selectionset);
            }
        }
        when GraphQL::FragmentSpread
        {
            my $fragment = $document.fragments{.name};
            
            validate-selectionset(:$document, :$schema, :$type,
                                  selectionset => $fragment.selectionset);
        }
        when GraphQL::QueryField
        {
            die "Field $_.name() not defined" unless $type.field(.name);
        }
    }

    return True;
}

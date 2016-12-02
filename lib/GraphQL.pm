use Data::Dump;
use Hash::Ordered;

unit module GraphQL;

use GraphQL::Types;
use GraphQL::Actions;
use GraphQL::Grammar;

sub build-schema(Str $schema) returns GraphQL::Schema is export
{
    GraphQL::Grammar.parse($schema,
                           actions => GraphQL::Actions.new,
                           rule => 'TypeSchema')
        or die "Failed to parse schema";

    $/.made;
}

sub parse-query(Str $query) returns GraphQL::Document is export
{
    GraphQL::Grammar.parse($query,
                           actions => GraphQL::Actions.new,
                           rule => 'Document')
        or die "Failed to parse query";

    $/.made;
}

sub ExecuteRequest(GraphQL::Schema :$schema,
                   GraphQL::Document :$query,
                   Str :$operationName,
                   :%variableValues,
                   :$initialValue) is export
{
    my $operation = $query.GetOperation($operationName);

    # Do something with variables

    given $operation.operation
    {
        when 'query'
        {
            return ExecuteQuery(:$operation,
                                :$schema,
                                :%variableValues,
                                :$initialValue);
        }
        when 'mutation'
        {
            say "Mutate!";
        }
    }
}

sub ExecuteQuery(GraphQL::Operation :$operation,
                 GraphQL::Schema :$schema,
                 :%variableValues,
                 :$initialValue)
{
    my $data = ExecuteSelectionSet(selectionSet => $operation.selectionset,
                                   objectType => $schema.type,
                                   objectValue => $initialValue,
                                   :%variableValues);

    return {
        data => $data
    };

}

sub ExecuteSelectionSet(:@selectionSet,
                        GraphQL::Object :$objectType,
                        :$objectValue,
                        :%variableValues)
{
    my $groupedFieldSet = CollectFields(:$objectType,
                                        :@selectionSet,
                                        :%variableValues);

    my $resultMap = Hash::Ordered.new;

    for $groupedFieldSet.kv -> $responseKey, @fields
    {
        my $fieldName = @fields[0].name;

        my $fieldType = $objectType.fields{$fieldName}.name or next;

        my $responseValue = ExecuteField(:$objectType, 
                                         :$objectValue,
                                         :@fields,
                                         :$fieldType,
                                         :%variableValues);

        $resultMap{$responseKey} = $responseValue;
    }

    return $resultMap;
}

sub ExecuteField(GraphQL::Object :$objectType,
                 :$objectValue,
                 :@fields,
                 :$fieldType,
                 :%variableValues)
{
    my $field = @fields[0];

    my $fieldName = $field.name;

    my %argumentValues;

    my $resolvedValue = ResolveFieldValue(:$objectType,
                                          :$objectValue,
                                          :$fieldName,
                                          :%argumentValues);

    return CompleteValue(:$fieldType,
                         :@fields,
                         :$resolvedValue,
                         :%variableValues);
}

sub ResolveFieldValue(GraphQL::Object :$objectType,
                      :$objectValue,
                      :$fieldName,
                      :%argumentValues)
{
    $objectType.fields{$fieldName}.resolve($objectValue, %argumentValues)
}

sub CompleteValue(:$fieldType, :@fields, :$resolvedValue, :%variableValues)
{
    return $resolvedValue;
}

sub CollectFields(GraphQL::Object :$objectType,
                  :@selectionSet,
                  :%variableValues,
                  :$visitedFragments = set())
{
    my $groupedFields = Hash::Ordered.new;

    for @selectionSet -> $selection
    {
        ... if $selection.directives;

        given $selection
        {
            when GraphQL::QueryField
            {
                $groupedFields{$selection.responseKey} = []
                    unless $groupedFields{$selection.responseKey}:exists;

                push $groupedFields{$selection.responseKey}, $selection;
            }
            when GraphQL::FragmentSpread
            {
                ...
            }
            when GraphQL::InlineFragment
            {
                ...
            }
        }
    }

    return $groupedFields;
}

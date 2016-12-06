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

    # Make sure schema root field has the introspection types
    
    $schema.introspectionfields;

    my %coercedVariableValues = CoerceVariableValues(:$schema,
                                                     :$operation,
                                                     :%variableValues);

    given $operation.operation
    {
        when 'query'
        {
            return ExecuteQuery(:$operation,
                                :$schema,
                                variableValues => %coercedVariableValues,
                                :$initialValue);
        }
        when 'mutation'
        {
            say "Mutate!";
        }
    }
}

sub CoerceVariableValues(GraphQL::Schema :$schema,
                         GraphQL::Operation :$operation,
                         :%variableValues)
{
    my %coercedValues;

    ...

    return %coercedValues;
}

sub ExecuteQuery(GraphQL::Operation :$operation,
                 GraphQL::Schema :$schema,
                 :%variableValues,
                 :$initialValue)
{
    my $data = ExecuteSelectionSet(selectionSet => $operation.selectionset,
                                   objectType => $schema.type,
                                   objectValue => $initialValue,
                                   :%variableValues,
                                   :$schema);

    return {
        data => $data
    };

}

sub ExecuteSelectionSet(:@selectionSet,
                        GraphQL::Object :$objectType,
                        :$objectValue,
                        :%variableValues,
                        :$schema)
{
    my $groupedFieldSet = CollectFields(:$objectType,
                                        :@selectionSet,
                                        :%variableValues);

    my $resultMap = Hash::Ordered.new;

    for $groupedFieldSet.kv -> $responseKey, @fields
    {
        my $fieldName = @fields[0].name;

        my $responseValue;

        if ($fieldName eq '__typename')  # Maybe I should do this elsewhere?
        {
            $responseValue = $objectType.name;
        }
        else
        {
            my $fieldType = $objectType.fields{$fieldName}.type or next;

            $responseValue = ExecuteField(:$objectType, 
                                          :$objectValue,
                                          :@fields,
                                          :$fieldType,
                                          :%variableValues,
                                          :$schema);
        }

        $resultMap{$responseKey} = $responseValue;
    }

    return $resultMap;
}

sub ExecuteField(GraphQL::Object :$objectType,
                 :$objectValue,
                 :@fields,
                 GraphQL::Type :$fieldType,
                 :%variableValues,
                 :$schema)
{
    my $field = @fields[0];

    my %argumentValues = CoerceArgumentValues(:$objectType,
                                              :$field,
                                              :%variableValues);

    my $resolvedValue = $objectType.fields{$field.name}
                                   .resolve(:$objectValue,
                                            :%argumentValues,
                                            :$schema);

    return CompleteValue(:$fieldType,
                         :@fields,
                         :result($resolvedValue),
                         :%variableValues,
                         :$schema);
     
}

sub CompleteValue(GraphQL::Type :$fieldType,
                  :@fields,
                  :$result,
                  :%variableValues,
                  :$schema)
{
    given $fieldType
    {
        when GraphQL::Object | GraphQL::Interface | GraphQL::Union
        {
            my $objectType = * ~~ GraphQL::Object 
                ?? $fieldType
                !! ResolveAbstractType(:$fieldType, :$result);

            my @subSelectionSet = MergeSelectionSets(:@fields);

            return ExecuteSelectionSet(:selectionSet(@subSelectionSet),
                                       :$objectType,
                                       :objectValue($result),
                                       :%variableValues,
                                       :$schema);
        }
        when GraphQL::Scalar
        {
            return $result // Nil;
        }
        default 
        {
            say $fieldType;
            die "Complete Value Unknown Type";
        }
    }

    return $result;
}

sub ResolveAbstractType(:$fieldType, :$results)
{
    die "ResolveAbstractType";
}

sub MergeSelectionSets(:@fields)
{
    gather
    {
        for @fields -> $field
        {
            take $_ for $field.selectionset;
        }
    }
}

#
# $objectType is the schema definition for the object
# $field is the query field
#
sub CoerceArgumentValues(GraphQL::Object :$objectType,
                         GraphQL::QueryField :$field,
                         :%variableValues)
{
    my %coercedValues;

    for $objectType.fields{$field.name}.args -> $arg
    {
        # ...if $field.args{$arg.name} is a variable, resolve it first
        
        %coercedValues{$arg.name} = $field.args{$arg.name} //
            $arg.defaultValue //
            die "Must provide $arg.name";

        # ...Coerce value to type
    }

    return %coercedValues;
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

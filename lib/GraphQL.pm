use Data::Dump;
use Hash::Ordered;

unit module GraphQL;

use GraphQL::Types;
use GraphQL::Actions;
use GraphQL::Grammar;
use GraphQL::Introspection;

sub build-schema(Str $schemastring) returns GraphQL::Schema is export
{
    # First add Introspection types

    my $actions = GraphQL::Actions.new;

    GraphQL::Grammar.parse($GraphQL-Introspection-Schema,
                           :$actions,
                           :rule('TypeSchema'))
        or die "Failed to parse Introspection Schema";

    my $schema = $/.made;

    # Then parse the specified schema string

    GraphQL::Grammar.parse($schemastring, 
                           :$schema, :$actions, :rule('TypeSchema'))
        or die "Failed to parse schema";

    die "Missing root query type $schema.query()" 
        unless $schema.queryType and $schema.queryType.kind ~~ 'OBJECT';

    # Then add meta-fields __schema and __type to the root type

    $schema.queryType.addfield(GraphQL::Field.new(
        name => '__type',
        type => $schema.type('__Type'),
        args => [ GraphQL::InputValue.new(
                      name => 'name',
                      type => GraphQL::Non-Null.new(
                          ofType => $GraphQLString
                      )
                  ) ],
        resolver => sub (:$name) { $schema.type($name) }
    ));

    $schema.queryType.addfield(GraphQL::Field.new(
        name => '__schema',
        type => GraphQL::Non-Null.new(
            ofType => $schema.type('__Schema')
        ),
        resolver => sub { $schema }
    ));

    return $schema;
}

sub parse-document(Str $query) returns GraphQL::Document is export
{
    GraphQL::Grammar.parse($query,
                           actions => GraphQL::Actions.new,
                           rule => 'Document')
        or die "Failed to parse query";

    $/.made;
}

sub ExecuteRequest(GraphQL::Schema :$schema,
                   GraphQL::Document :$document,
                   Str :$operationName,
                   :%variableValues,
                   :$initialValue) is export
{
    my $operation = $document.GetOperation($operationName);

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
                                :$initialValue,
                                :$document);
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
                 GraphQL::Document :$document,
                 :%variableValues,
                 :$initialValue)
{
    my $data = ExecuteSelectionSet(selectionSet => $operation.selectionset,
                                   objectType => $schema.queryType,
                                   objectValue => $initialValue,
                                   :%variableValues,
                                   :$document);

    return %(
        data => $data
    );

}

sub ExecuteSelectionSet(:@selectionSet,
                        GraphQL::Object :$objectType,
                        :$objectValue,
                        :%variableValues,
                        GraphQL::Document :$document)
{
    my $groupedFieldSet = CollectFields(:$objectType,
                                        :@selectionSet,
                                        :%variableValues,
                                        :$document);

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
            my $fieldType = $objectType.field($fieldName).type or next;

            $responseValue = ExecuteField(:$objectType, 
                                          :$objectValue,
                                          :@fields,
                                          :$fieldType,
                                          :%variableValues);
        }

        $resultMap{$responseKey} = $responseValue;
    }

    return $resultMap;
}

sub ExecuteField(GraphQL::Object :$objectType,
                 :$objectValue,
                 :@fields,
                 GraphQL::Type :$fieldType,
                 :%variableValues)
{
    my $field = @fields[0];

    my %argumentValues = CoerceArgumentValues(:$objectType,
                                              :$field,
                                              :%variableValues);

    my $resolvedValue = $objectType.field($field.name)
                                   .resolve(:$objectValue,
                                            :%argumentValues);

    return CompleteValue(:$fieldType,
                         :@fields,
                         :result($resolvedValue),
                         :%variableValues);
     
}

sub CompleteValue(GraphQL::Type :$fieldType,
                  :@fields,
                  :$result,
                  :%variableValues)
{
    given $fieldType
    {
        when GraphQL::Non-Null
        {
            my $completedResult = CompleteValue(:fieldType($fieldType.ofType),
                                                :@fields,
                                                :$result,
                                                :%variableValues);
            
            die "Null in non-null type" unless $completedResult.defined;

            return $completedResult;
        }
        
        return Nil unless $result.defined;

        when GraphQL::List
        {
            die "Must return a List" unless $result ~~ List | Seq;

            return $result.map({CompleteValue(:fieldType($fieldType.ofType),
                                              :@fields,
                                              :result($_),
                                              :%variableValues)});
        }

        when GraphQL::Scalar
        {
            return $result // Nil;
        }

        when GraphQL::Object | GraphQL::Interface | GraphQL::Union
        {
            my $objectType = * ~~ GraphQL::Object 
                ?? $fieldType
                !! ResolveAbstractType(:$fieldType, :$result);

            my @subSelectionSet = MergeSelectionSets(:@fields);

            return ExecuteSelectionSet(:selectionSet(@subSelectionSet),
                                       :$objectType,
                                       :objectValue($result),
                                       :%variableValues);
        }

        default 
        {
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

    for $objectType.field($field.name).args -> $arg
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
                  :$visitedFragments = set(),
                  GraphQL::Document :$document)
{
    my $groupedFields = Hash::Ordered.new;

    for @selectionSet -> $selection
    {
#        ... if $selection.directives;

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
                my $fragmentSpreadName = $selection.name;

                next if $fragmentSpreadName ∈ $visitedFragments;

                my $fragment = $document.fragments{$fragmentSpreadName} or next;

                my $fragmentType = $fragment.onType;

                next unless $objectType.fragment-applies($fragmentType);

                my @fragmentSelectionSet = $fragment.selectionset;

                my $fragmentGroupedFieldSet = CollectFields(
                    :$objectType,
                    :selectionSet(@fragmentSelectionSet),
                    :%variableValues,
                    :$visitedFragments,
                    :$document);

                for $fragmentGroupedFieldSet.kv -> $responseKey, @fragmentGroup
                {
                    $groupedFields{$responseKey} = []
                        unless $groupedFields{$responseKey}:exists;
                    push $groupedFields{$responseKey}, |@fragmentGroup;
                }
            }
            when GraphQL::InlineFragment
            {
                ...
            }
        }
    }

    return $groupedFields;
}

use Data::Dump;
use Hash::Ordered;

unit module GraphQL;

use GraphQL::Types;
use GraphQL::Actions;
use GraphQL::Grammar;
use GraphQL::Introspection;

sub add-meta-fields(:$schema)
{
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
}

multi sub graphql-schema(*@types, :$query, :$mutation)
    returns GraphQL::Schema is export
{
    GraphQL::Grammar.parse($GraphQL-Introspection-Schema,
                           :actions(GraphQL::Actions.new),
                           :rule('TypeSchema'))
        or die "Failed to parse Introspection Schema";

    my $schema = $/.made;

    for @types -> $type
    {
        $schema.addtype($type)
    }

    if ($query)
    {
        $schema.query = $query if $query;
        add-meta-fields(:$schema);
    }

    if ($mutation)
    {
        $schema.mutation = $mutation;
    }

    return $schema;
}

multi sub graphql-schema(Str $schemastring)
    returns GraphQL::Schema is export
{
    my $schema = graphql-schema;

    my $actions = GraphQL::Actions.new(:$schema);

    GraphQL::Grammar.parse($schemastring, :$actions, :rule('TypeSchema'))
        or die "Failed to parse schema";

    add-meta-fields(:$schema);

    return $schema;
}

sub graphql-document(Str $query)
    returns GraphQL::Document is export
{
    GraphQL::Grammar.parse($query,
                           actions => GraphQL::Actions.new,
                           rule => 'Document')
        or die "Failed to parse query";

    $/.made;
}

sub graphql-execute(Str $query?,
                    GraphQL::Schema :$schema,
                    GraphQL::Document :$document = graphql-document($query),
                    Str :$operationName,
                    :%variables,
                    :$initialValue) is export
{
    die "Missing root query type $schema.query()" 
        unless $schema.queryType and $schema.queryType.kind ~~ 'OBJECT';

    my $operation = $document.GetOperation($operationName);

    my %coercedVariableValues = CoerceVariableValues(:$schema,
                                                     :$operation,
                                                     :%variables);

    my $objectValue = $initialValue // 0;

    given $operation.operation
    {
        when 'query'
        {
            return ExecuteQuery(:$operation,
                                :$schema,
                                variables => %coercedVariableValues,
                                :$objectValue,
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
                         :%variables)
{
    my %coercedValues;

    ...

    return %coercedValues;
}

sub ExecuteQuery(GraphQL::Operation :$operation,
                 GraphQL::Schema :$schema,
                 GraphQL::Document :$document,
                 :%variables,
                 :$objectValue! is rw) returns Hash
{
    my $data = ExecuteSelectionSet(selectionSet => $operation.selectionset,
                                   objectType => $schema.queryType,
                                   :$objectValue,
                                   :%variables,
                                   :$document);

    return {
        data => $data
    };

}

sub ExecuteSelectionSet(:@selectionSet,
                        GraphQL::Object :$objectType,
                        :$objectValue! is rw,
                        :%variables,
                        GraphQL::Document :$document)
{
    my $groupedFieldSet = CollectFields(:$objectType,
                                        :@selectionSet,
                                        :%variables,
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
                                          :%variables);
        }

        $resultMap{$responseKey} = $responseValue;
    }

    return $resultMap;
}

sub ExecuteField(GraphQL::Object :$objectType,
                 :$objectValue! is rw,
                 :@fields,
                 GraphQL::Type :$fieldType,
                 :%variables)
{
    my $field = @fields[0];

    my $fieldName = $field.name;

    my %argumentValues = CoerceArgumentValues(:$objectType,
                                              :$field,
                                              :%variables);

    my $resolvedValue = ResolveFieldValue(:$objectType,
                                          :$objectValue,
                                          :$fieldName,
                                          :%argumentValues);

    return CompleteValue(:$fieldType,
                         :@fields,
                         :result($resolvedValue),
                         :%variables);
     
}

sub ResolveFieldValue(GraphQL::Object :$objectType,
                      :$objectValue! is rw,
                      :$fieldName,
                      :%argumentValues)
{
    my $field = $objectType.field($fieldName) or return;

    if not $objectValue and $objectType.resolver
    {
        $objectValue = call-with-right-args($objectType.resolver,
                                            |%argumentValues);
    }

    if $field.resolver
    {
        return call-with-right-args($field.resolver,
                                    :$objectValue,
                                    |%argumentValues);
    }

    if $objectValue.^can($fieldName)
    {
        return $objectValue."$fieldName"();
    }

    die "No resolver for $objectType.name() or $fieldName";
}

sub call-with-right-args(Sub $sub, *%allargs)
{
    my %args;
    for $sub.signature.params -> $p
    {
        if ($p.named)
        {
            for $p.named_names -> $param_name
            {
                if %allargs{$param_name}:exists
                {
                    %args{$param_name} = %allargs{$param_name};
                    last;
                }
            }
        }
    }

    $sub(|%args);
}

sub CompleteValue(GraphQL::Type :$fieldType,
                  :@fields,
                  :$result,
                  :%variables)
{
    given $fieldType
    {
        when GraphQL::Non-Null
        {
            my $completedResult = CompleteValue(:fieldType($fieldType.ofType),
                                                :@fields,
                                                :$result,
                                                :%variables);
            
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
                                              :%variables)});
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

            my $objectValue = $result;

            return ExecuteSelectionSet(:selectionSet(@subSelectionSet),
                                       :$objectType,
                                       :$objectValue,
                                       :%variables);
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
                         :%variables)
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
                  :%variables,
                  :$visitedFragments is copy = ∅,
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

                $visitedFragments ∪= $fragmentSpreadName;

                my $fragment = $document.fragments{$fragmentSpreadName} or next;

                my $fragmentType = $fragment.onType;

                next unless $objectType.fragment-applies($fragmentType);

                my @fragmentSelectionSet = $fragment.selectionset;

                my $fragmentGroupedFieldSet = CollectFields(
                    :$objectType,
                    :selectionSet(@fragmentSelectionSet),
                    :%variables,
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
                my $fragmentType = $selection.onType;

                next if $fragmentType.defined and
                    not $objectType.fragment-applies($fragmentType);

                my @fragmentSelectionSet = $selection.selectionset;

                my $fragmentGroupedFieldSet = CollectFields(
                    :$objectType,
                    :selectionSet(@fragmentSelectionSet),
                    :%variables,
                    :$visitedFragments,
                    :$document);
                
                for $fragmentGroupedFieldSet.kv -> $responseKey, @fragmentGroup
                {
                    $groupedFields{$responseKey} = []
                        unless $groupedFields{$responseKey}:exists;

                    push $groupedFields{$responseKey}, |@fragmentGroup;
                }
            }
        }
    }

    return $groupedFields;
}

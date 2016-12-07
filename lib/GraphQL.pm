use Data::Dump;
use Hash::Ordered;

unit module GraphQL;

use GraphQL::Types;
use GraphQL::Actions;
use GraphQL::Grammar;
use GraphQL::Introspection;

sub GetName(:$objectValue)              { $objectValue.name }
sub GetKind(:$objectValue)              { $objectValue.kind }
sub GetDescription(:$objectValue)       { $objectValue.description }
sub GetArgs(:$objectValue)              { $objectValue.args }
sub GetType(:$objectValue)              { $objectValue.type }
sub GetIsDeprecated(:$objectValue)      { $objectValue.isDeprecated }
sub GetDeprecationReason(:$objectValue) { $objectValue.deprecationReason }
sub GetDefaultValue(:$objectValue)      { $objectValue.defaultValue }

my %GraphQL-Introspection-Resolvers =

__Schema =>
{
    types => sub (GraphQL::Schema :$schema) { $schema.types.values.eager },
    queryType => sub (GraphQL::Schema :$schema) { $schema.type() },
    mutationType => sub (GraphQL::Schema :$schema)
                        { $schema.type($schema.mutation) },
    directives => sub (GraphQL::Schema :$schema) { die }
},

__Type => 
{
    kind => &GetKind,
    name => &GetName,
    description => &GetDescription,

    fields => sub (:$objectValue, Bool :$includeDeprecated)
    {
        return unless $objectValue ~~ GraphQL::Object | GraphQL::Interface;
        $objectValue.fields.values
                    .grep({.name !~~ /^__/ and
                               ($includeDeprecated or not .isDeprecated) })
                    .eager
    },

    interfaces => sub (:$objectValue)
    {
        return unless $objectValue ~~ GraphQL::Object;
        $objectValue.interfaces
    },

    possibleTypes => sub (:$objectValue)
    {
        return unless $objectValue ~~ GraphQL::Interface | GraphQL::Union;
        $objectValue.possibleTypes.keys
    },

    enumValues => sub (:$objectValue, :$includeDeprecated)
    {
        return unless $objectValue ~~ GraphQL::Enum;
        $objectValue.enumValues.keys
                    .grep({$includeDeprecated or not .isDeprecated}).eager
    },

    ofType => sub (:$objectValue)
    { 
        return unless $objectValue ~~ GraphQL::Non-Null | GraphQL::List;
        $objectValue.ofType
    }
},

__Field =>
{
    name => &GetName,
    description => &GetDescription,
    args => &GetArgs,
    type => &GetType,
    isDeprecated => &GetIsDeprecated,
    deprecationReason => &GetDeprecationReason
},

__InputValue =>
{
    name => &GetName,
    description => &GetDescription,
    type => &GetType,
    defaultValue => &GetDefaultValue    
},

__EnumValue =>
{
    name => &GetName,
    description => &GetDescription,
    isDeprecated => &GetIsDeprecated,
    deprecationReason => &GetDeprecationReason
},

__Directive => 
{
    name => &GetName,
    description => &GetDescription,
    locations => sub (GraphQL::Directive :$objectValue)
    {
        $objectValue.locations
    },
    args => &GetArgs
};

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
        unless $schema.type() and $schema.type().kind ~~ 'OBJECT';

    # Then add meta-fields __schema and __type to the root type

    $schema.type().fields<__type> = GraphQL::Field.new(
        name => '__type',
        type => $schema.type('__Type'),
        args => [ GraphQL::InputValue.new(
                      name => 'name',
                      type => GraphQL::Non-Null.new(
                          ofType => $GraphQLString
                      )
                  ) ],
        resolver => sub (:$name, :$schema) { $schema.type($name) }
    );

    $schema.type().fields<__schema> = GraphQL::Field.new(
        name => '__schema',
        type => GraphQL::Non-Null.new(
            ofType => $schema.type('__Schema')
        ),
        resolver => sub (GraphQL::Schema :$schema) { $schema }
    );

    $schema.resolvers(%GraphQL-Introspection-Resolvers);

    return $schema;
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

    return %(
        data => $data
    );

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
            say $objectType.name;
            say $objectType.Str;
            say $fieldName;
            
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
        when GraphQL::Non-Null
        {
            my $completedResult = CompleteValue(:fieldType($fieldType.ofType),
                                                :@fields,
                                                :$result,
                                                :%variableValues,
                                                :$schema);
            
            die "Null in non-null type" unless $completedResult.defined;

            return $completedResult;
        }
        
        return Nil unless $result.defined;

        when GraphQL::List
        {
            die "Must return a List" unless $result ~~ List;

            return $result.map({CompleteValue(:fieldType($fieldType.ofType),
                                              :@fields,
                                              :result($_),
                                              :%variableValues,
                                              :$schema)});
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
                                       :%variableValues,
                                       :$schema);
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

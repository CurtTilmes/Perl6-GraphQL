use Hash::Ordered;

unit module GraphQL;

use GraphQL::Introspection;
use GraphQL::Grammar;
use GraphQL::Actions;
use GraphQL::Types;

my Set $defaultTypes = set $GraphQLInt, $GraphQLFloat, $GraphQLString,
                           $GraphQLBoolean, $GraphQLID;

class GraphQL::Schema
{
    has GraphQL::Type %!types;
    has Str $.query is rw = 'Query';
    has Str $.mutation is rw;

    multi method new(:$queryType, :$mutationType, :$resolvers, *@types)
    {
        my $schema = GraphQL::Schema.bless;

        $defaultTypes.keys.map({ $schema.addtype($_) });

        my $actions = GraphQL::Actions.new(:$schema);

        GraphQL::Grammar.parse($GraphQL-Introspection-Schema,
                               :$actions,
                               rule => 'TypeSchema')
            or die "Failed to parse Introspection Schema";

        for @types -> $type
        {
            $schema.addtype($type)
        }

        if ($queryType)
        {
            $schema.query = $queryType if $queryType;
            $schema!add-meta-fields;
        }

        if ($mutationType)
        {
            $schema.mutation = $mutationType;
        }

        $schema.resolvers($resolvers) if $resolvers;

        return $schema;
    }

    multi method new(Str $schemastring, :$resolvers)
    {
        my $schema = GraphQL::Schema.new;
        
        my $actions = GraphQL::Actions.new(:$schema);

        GraphQL::Grammar.parse($schemastring, :$actions, :rule('TypeSchema'))
            or die "Failed to parse schema";

        $schema!add-meta-fields;

        $schema.resolvers($resolvers) if $resolvers;

        return $schema;
    }

    method !add-meta-fields
    {
        self.queryType.addfield(GraphQL::Field.new(
            name => '__type',
            type => self.type('__Type'),
            args => [ GraphQL::InputValue.new(
                          name => 'name',
                          type => GraphQL::Non-Null.new(
                              ofType => $GraphQLString
                              )
                          )
                    ],
            resolver => sub (:$name) { self.type($name) }
        ));

        self.queryType.addfield(GraphQL::Field.new(
            name => '__schema',
            type => GraphQL::Non-Null.new(
                ofType => self.type('__Schema')
            ),
            resolver => sub { self }
        ));
    }

    method types { %!types.values }

    method addtype(GraphQL::Type $newtype)
    {
	%!types{$newtype.name} = $newtype
    }

    method type($typename) { %!types{$typename} }

    method queryType returns GraphQL::Object { %!types{$!query} }

    method mutationType returns GraphQL::Object
    {
        return unless $!mutation and %!types{$!mutation};
        %!types{$!mutation}
    }

    method directives { [] }

    method Str
    {
        my $str = '';

        for %!types.kv -> $typename, $type
        {
            next if $type ∈ $defaultTypes or $typename ~~ /^__/;
            $str ~= $type.Str ~ "\n";
        }

        $str ~= "schema \{\n";
	$str ~= "  query: $!query\n";
        $str ~= "  mutation: $!mutation\n" if $!mutation;
	$str ~= "}\n";
    }

    method document(Str $query) returns GraphQL::Document
    {
        my $grammar = GLOBAL::GraphQL::{'Grammar'};
        my $actions = GLOBAL::GraphQL::{'Actions'};

        $grammar.parse($query,
                       :actions($actions.new(:schema(self))),
                       rule => 'Document')
            or die "Failed to parse query";
        
        $/.made;
    }

    method resolvers(%resolvers)
    {
        for %resolvers.kv -> $type, $obj
        {
            die "Undefined object $type" unless %!types{$type};

            if ($obj ~~ Associative)
            {
                for $obj.kv -> $field, $resolver
                {
                    die "Undefined field $field for $type"
                        unless %!types{$type}.field($field);
                    
                    %!types{$type}.field($field).resolver = $resolver;
                }
            }
            else
            {
                %!types{$type}.resolver = $obj;
            }
        }
    }

    # ExecuteRequest() == $schema.execute()
    method execute(Str $query?,
                   GraphQL::Document :$document = self.document($query),
                   Str :$operationName,
                   :%variables,
                   :$initialValue)
    {
        die "Missing root query type $!query()"
            unless self.queryType
            and self.queryType.kind ~~ 'OBJECT';

        my $operation = $document.GetOperation($operationName);

        my %coercedVariableValues = CoerceVariableValues(:$operation,
                                                         :%variables);

        my $objectValue = $initialValue // 0;

        given $operation.operation
        {
            when 'query'
            {
                return self.ExecuteQuery(:$operation,
                                         variables => %coercedVariableValues,
                                         :$objectValue,
                                         :$document);
            }
            when 'mutation'
            {
                die "Missing root mutation type $!mutation"
                    unless self.mutationType
                    and self.mutationType.kind ~~ 'OBJECT';

                return self.ExecuteMutation(:$operation,
                                            variables => %coercedVariableValues,
                                            :$objectValue,
                                            :$document);
            }
        }
    }

    method ExecuteMutation(GraphQL::Operation :$operation,
                           :%variables,
                           :$objectValue! is rw,
                           GraphQL::Document:$document)
    {
        # Serially!!
        my $data = self.ExecuteSelectionSet(selectionSet =>
                                            $operation.selectionset,
                                            objectType => $.mutationType,
                                            :$objectValue,
                                            :%variables,
                                            :$document);

        return {
            data => $data
        };
    }

    method ExecuteQuery(GraphQL::Operation :$operation,
                        GraphQL::Document :$document,
                        :%variables,
                        :$objectValue! is rw) returns Hash
    {
        # Parallel!
        my $data = self.ExecuteSelectionSet(selectionSet =>
                                            $operation.selectionset,
                                            objectType => self.queryType,
                                            :$objectValue,
                                            :%variables,
                                            :$document);

        return {
            data => $data
        };
    }

    method ExecuteSelectionSet(:@selectionSet,
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

            if ($fieldName eq '__typename')
            {
                $responseValue = $objectType.name;
            }
            else
            {
                my $fieldType = $objectType.field($fieldName).type
                    or die qq{Cannot query field "$fieldName" } ~
                           qq{on type "$objectType.name()".};

                $responseValue = self.ExecuteField(:$objectType, 
                                                   :$objectValue,
                                                   :@fields,
                                                   :$fieldType,
                                                   :%variables,
                                                   :$document);
            }

            $resultMap{$responseKey} = $responseValue;
        }

        return $resultMap;
    }

    method ExecuteField(GraphQL::Object :$objectType,
                        :$objectValue! is rw,
                        :@fields,
                        GraphQL::Type :$fieldType,
                        :%variables,
                        :$document)
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

        return self.CompleteValue(:$fieldType,
                                  :@fields,
                                  :result($resolvedValue),
                                  :%variables,
                                  :$document);
    }

    method CompleteValue(GraphQL::Type :$fieldType,
                         :@fields,
                         :$result,
                         :%variables,
                         :$document)
    {
        given $fieldType
        {
            when GraphQL::Non-Null
            {
                my $completedResult = 
                    self.CompleteValue(:fieldType($fieldType.ofType),
                                       :@fields,
                                       :$result,
                                       :%variables,
                                       :$document);
            
                die "Null in non-null type" unless $completedResult.defined;

                return $completedResult;
            }
        
            return unless $result.defined;

            when GraphQL::List
            {
                die "Must return a List" unless $result ~~ List | Seq;
                
                return $result.map({ self.CompleteValue(
                                         :fieldType($fieldType.ofType),
                                         :@fields,
                                         :result($_),
                                         :%variables,
                                         :$document)});
            }

            when GraphQL::Scalar
            {
                return $result // Nil;
            }

            when GraphQL::Object | GraphQL::Interface | GraphQL::Union
            {
                my $objectType = * ~~ GraphQL::Object 
                    ?? $fieldType
                    !! self.ResolveAbstractType(:$fieldType, :$result);

                my @subSelectionSet = MergeSelectionSets(:@fields);

                my $objectValue = $result;

                return self.ExecuteSelectionSet(:selectionSet(@subSelectionSet),
                                                :$objectType,
                                                :$objectValue,
                                                :%variables,
                                                :$document);
            }

            default 
            {
                die "Complete Value Unknown Type";
            }
        }
    }

    method ResolveAbstractType(:$fieldType, :$results)
    {
        die "ResolveAbstractType";
    }
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

sub CoerceVariableValues(GraphQL::Operation :$operation,
                         :%variables)
{
    my %coercedValues;

    for $operation.vars -> $v
    {
        unless %variables{$v.name}
        {
            if $v.defaultValue.defined
            {
                %coercedValues{$v.name} = $v.defaultValue;
            }
            if $v.type ~~ GraphQL::Non-Null
            {
                die "Must set value for Non-Nullable type $v.type.name() "
                    ~ "for variable \$$v.name"
            }
            next;
        }
        %coercedValues{$v.name} = %variables{$v.name};
    }

    return %coercedValues;
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
        my $value = $field.args{$arg.name};

        if $value ~~ GraphQL::Variable
        {
            $value = %variables{$value.name} // $arg.defaultValue //
                die "Must provide $arg.name()";
        }

        %coercedValues{$arg.name} = $value //
            $arg.defaultValue //
            die "Must provide $arg.name()";
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
}


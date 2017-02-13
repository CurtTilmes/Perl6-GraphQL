unit module GraphQL::Execution;

use GraphQL::Types;
use GraphQL::Response;

my Set $background-methods;

multi sub trait_mod:<is>(Method $m, :$graphql-background!) is export
{
    $background-methods ∪= $m;
}

sub ExecuteRequest(:$document,
                   Str :$operationName,
                   :%variables,
                   :$initialValue,
                   :$schema,
                   :%session) is export
{
    my $operation = $document.GetOperation($operationName);

    my $selectionSet = $operation.selectionset;

    my %coercedVariableValues = CoerceVariableValues(:$operation,
                                                     :%variables);

    my $objectValue = $initialValue // 0;

    my $objectType = $operation.operation eq 'mutation'
                     ?? $schema.mutationType
                     !! $schema.queryType;

    ExecuteSelectionSet(:$selectionSet,
                        :$objectType,
                        :$objectValue,
                        :%variables,
                        :$document,
                        :%session);
}

sub ExecuteSelectionSet(:@selectionSet,
                        GraphQL::Object :$objectType,
                        :$objectValue! is rw,
                        :%variables,
                        GraphQL::Document :$document,
                        :%session)
{
    my @groupedFieldSet = CollectFields(:$objectType,
                                        :@selectionSet,
                                        :%variables,
                                        :$document);
    my @results;

    for @groupedFieldSet -> $p
    {
        my $responseKey = $p.key;
        my @fields = |$p.value;

        my $fieldName = @fields[0].name;

        my $responseValue;

        my $fieldType = $objectType.field($fieldName).type
            or die qq{Cannot query field '$fieldName' } ~
                qq{on type '$objectType.name()'.};
            
        $responseValue = ExecuteField(:$objectType,
                                      :$objectValue,
                                      :@fields,
                                      :$fieldType,
                                      :%variables,
                                      :$document,
                                      :%session);

        my $type = $fieldType ~~ GraphQL::Interface | GraphQL::Union
            ?? GraphQL::Object
            !! $fieldType;

        push @results, GraphQL::Response.new(:$type,
                                             name => $responseKey,
                                             value => $responseValue);
    }

    return @results;
}

sub ExecuteField(GraphQL::Object :$objectType,
                 :$objectValue! is rw,
                 :@fields,
                 GraphQL::Type :$fieldType,
                 :%variables,
                 :$document,
                 :%session)
{
    my $field = @fields[0];

    my $fieldName = $field.name;

    my %argumentValues = CoerceArgumentValues(:$objectType,
                                              :$field,
                                              :%variables);

    my $resolvedValue = ResolveFieldValue(:$objectType,
                                          :$objectValue,
                                          :$fieldName,
                                          :%argumentValues,
                                          :%session);

    if $resolvedValue ~~ Promise
    {
        return $resolvedValue.then(
            {
                CompleteValue(:$fieldType,
                              :@fields,
                              :result($resolvedValue.result),
                              :%variables,
                              :$document)
            });
    }
    else
    {
        return CompleteValue(:$fieldType,
                             :@fields,
                             :result($resolvedValue),
                             :%variables,
                             :$document);
    }
}

sub CompleteValue(GraphQL::Type :$fieldType,
                  :@fields,
                  :$result,
                  :%variables,
                  :$document)
{
    given $fieldType
    {
        when GraphQL::Enum
        {
            return $fieldType.valid($result) ?? $result !! Nil;
        }
        
        when GraphQL::Scalar
        {
            return $result;
        }
        
        when GraphQL::Non-Null
        {
            my $completedResult = CompleteValue(:fieldType($fieldType.ofType),
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
            
            my $list = $result.map({ CompleteValue(
                                         :fieldType($fieldType.ofType),
                                         :@fields,
                                         :result($_),
                                         :%variables,
                                         :$document) });
            return $list;
        }
        
        when GraphQL::Object | GraphQL::Interface | GraphQL::Union
        {
            my $objectType = $fieldType ~~ GraphQL::Object
                ?? $fieldType
                !! ResolveAbstractType(:$fieldType, :$result);
            
            my @subSelectionSet = MergeSelectionSets(:@fields);
            
            my $objectValue = $result;
            
            return ExecuteSelectionSet(:selectionSet(@subSelectionSet),
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

sub ResolveAbstractType(:$fieldType, :$result)
{
    $fieldType.possibleTypes.first: { .name eq $result.WHAT.^name }
}

sub MergeSelectionSets(:@fields)
{
    my @list;

    for @fields -> $field
    {
        for $field.selectionset -> $sel
        {
            push @list, $sel;
        }
    }

    return @list;
}

sub CoerceVariableValues(GraphQL::Operation :$operation,
                         :%variables)
{
    my %coercedValues;

    for $operation.vars -> $v
    {
        %coercedValues{$v.name} = $v.type.coerce(%variables{$v.name}
                                                 // $v.defaultValue);
    }

    return %coercedValues;
}

sub ReplaceVariable(:$value, :%variables)
{
    given $value
    {
        when GraphQL::Variable
        {
            return %variables{$value.name}:exists
                ?? %variables{$value.name}
                !! Nil;
        }
        when Hash
        {
            for $value.kv -> $k, $v
            {
                $value{$k} = ReplaceVariable(value => $v, :%variables);
            }
        }
        when List
        {
            for $value.kv -> $k, $v
            {
                $value[$k] = ReplaceVariable(value => $v, :%variables);
            }
        }
    }
    return $value;
}

sub CoerceArgumentValues(GraphQL::Object :$objectType,
                         GraphQL::QueryField :$field,
                         :%variables)
{
    my %coercedValues;

    for $objectType.field($field.name).args -> $arg
    {
        my $value = $field.args{$arg.name};

        $value = ReplaceVariable(:$value, :%variables);

        $value //= $arg.defaultValue // die "Must provide $arg.name()";

        %coercedValues{$arg.name} = $arg.type.coerce($value);
    }

    return %coercedValues;
}

sub CollectFields(GraphQL::Object :$objectType,
                  :@selectionSet,
                  :%variables,
                  :$visitedFragments is copy = ∅,
                  GraphQL::Document :$document)
{
    my %groupedFields;
    my @responsekeys;

    for @selectionSet -> $selection
    {
        if $selection.directives<skip>
        {
            given $selection.directives<skip><if>
            {
                when Bool
                {
                    next if $_;
                }
                when GraphQL::Variable and $_.type ~~ GraphQL::Boolean
                {
                    next if %variables{$_.name};
                }
            }
        }

        if $selection.directives<include>
        {
            given $selection.directives<include><if>
            {
                when Bool
                {
                    next unless $_;
                }
                when GraphQL::Variable and $_.type ~~ GraphQL::Boolean
                {
                    next unless %variables{$_.name};
                }
            }
        }

        given $selection
        {
            when GraphQL::QueryField
            {
                unless %groupedFields{$selection.responseKey}:exists
                {
                    %groupedFields{$selection.responseKey} = [];
                    push @responsekeys, $selection.responseKey;
                }

                push %groupedFields{$selection.responseKey}, $selection;
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

                my @fragmentGroupedFieldSet = CollectFields(
                    :$objectType,
                    :selectionSet(@fragmentSelectionSet),
                    :%variables,
                    :$visitedFragments,
                    :$document);

                for @fragmentGroupedFieldSet -> $p
                {
                    my $responseKey = $p.key;
                    my @fragmentGroup = |$p.value;

                    unless %groupedFields{$responseKey}:exists
                    {
                        %groupedFields{$responseKey} = [];
                        push @responsekeys, $responseKey;
                    }
                    push %groupedFields{$responseKey}, |@fragmentGroup;
                }
            }

            when GraphQL::InlineFragment
            {
                my $fragmentType = $selection.onType;

                next if $fragmentType.defined and
                    not $objectType.fragment-applies($fragmentType);

                my @fragmentSelectionSet = $selection.selectionset;

                my @fragmentGroupedFieldSet = CollectFields(
                    :$objectType,
                    :selectionSet(@fragmentSelectionSet),
                    :%variables,
                    :$visitedFragments,
                    :$document);
                
                for @fragmentGroupedFieldSet -> $p
                {
                    my $responseKey = $p.key;
                    my @fragmentGroup = |$p.value;

                    unless %groupedFields{$responseKey}:exists
                    {
                        %groupedFields{$responseKey} = [];
                        push @responsekeys, $responseKey;
                    }

                    push %groupedFields{$responseKey}, |@fragmentGroup;
                }
            }
        }
    }

    return @responsekeys.map( { $_ => %groupedFields{$_} } );
}

sub ResolveArgs(Signature $sig, *%allargs)
{
    my %args;

    for $sig.params -> $p
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

    return %args;
}

sub ResolveFieldValue(GraphQL::Object :$objectType,
                      :$objectValue!,
                      :$fieldName,
                      :%argumentValues,
                      :%session)
{
    my $field = $objectType.field($fieldName) or return;

    if $field.resolver
    {
        my $args = ResolveArgs($field.resolver.signature,
                               :$objectValue,
                               |%argumentValues,
                               |%session);

        if $field.resolver ~~ Sub
        {
            $field.resolver.(|$args);
        }
        elsif $field.resolver ~~ Method
        {
            if ($objectValue)
            {
                if $field.resolver ∈ $background-methods
                {
                    start $objectValue."$fieldName"(|$args)
                }
                else
                {
                    $objectValue."$fieldName"(|$args)
                }
            }
            else
            {
                if $field.resolver ∈ $background-methods
                {
                    start $field.resolver.package."$fieldName"(|$args)
                }
                else
                {
                    $field.resolver.package."$fieldName"(|$args)
                }
            }
        }
    }
    elsif $objectValue ~~ Hash and $objectValue{$fieldName}:exists
    {
        $objectValue{$fieldName};
    }
    elsif $objectValue.^lookup($fieldName) -> $method
    {
        $objectValue."$fieldName"(|ResolveArgs($method.signature,
                                               :$objectValue,
                                               |%argumentValues))
    }
}

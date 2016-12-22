unit module GraphQL;

use GraphQL::Introspection;
use GraphQL::Grammar;
use GraphQL::Actions;
use GraphQL::Types;
use GraphQL::Response;

my Set $defaultTypes = set $GraphQLInt, $GraphQLFloat, $GraphQLString,
                           $GraphQLBoolean, $GraphQLID;

my Set $background-methods;

multi sub trait_mod:<is>(Method $m, :$graphql-background!) is export
{
    $background-methods ∪= $m;
}

class GraphQL::Schema
{
    has GraphQL::Type %!types;
    has GraphQL::Directive @.directives;
    has Str $.query is rw = 'Query';
    has Str $.mutation is rw;
    has Str $.subscription is rw;
    has @.errors;

    multi method new(:$query, :$mutation, :$subscription, :$resolvers, *@types)
        returns GraphQL::Schema
    {
        my $schema = GraphQL::Schema.bless;

        $schema.add-type($defaultTypes.keys);

        my $actions = GraphQL::Actions.new(:$schema);

        GraphQL::Grammar.parse($GraphQL-Introspection-Schema,
                               :$actions,
                               rule => 'TypeSchema')
            or die "Failed to parse Introspection Schema";

        $schema.add-type(@types);
        $schema.query        = $query        if $query;
        $schema.mutation     = $mutation     if $mutation;
        $schema.subscription = $subscription if $subscription;

        $schema.resolvers($resolvers) if $resolvers;

        return $schema;
    }

    multi method new(Str $schemastring, :$resolvers)
        returns GraphQL::Schema
    {
        my $schema = GraphQL::Schema.new;
        
        my $actions = GraphQL::Actions.new(:$schema);

        GraphQL::Grammar.parse($schemastring, :$actions, :rule('TypeSchema'))
            or die "Failed to parse schema";

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

    has %!resolved;

    method resolve-type(GraphQL::Type $type)
    {
        return $type if $type ~~ GraphQL::Object and %!resolved{$type.name}++;

        given $type
        {
            when GraphQL::LazyType
            {
                my $realtype = self.type($type.name);

                die "Can't resolve $type.name()"
                    if $realtype ~~ GraphQL::LazyType;

                return $realtype;
            }
            when GraphQL::Interface
            {
                $type.fieldlist .= map({ self.resolve-type($_) });
            }
            when GraphQL::Object
            {
                $type.fieldlist .= map({ self.resolve-type($_) });
                $type.interfaces .= map({ self.resolve-type($_) });
            }
            when GraphQL::InputObjectType
            {
                $type.inputFields .= map({ self.resolve-type($_) });
            }
            when GraphQL::Union
            {
                $type.possibleTypes .= map({ self.resolve-type($_) });;
            }
            when GraphQL::Non-Null | GraphQL::List
            {
                $type.ofType = self.resolve-type($type.ofType);
            }
            when GraphQL::Field
            {
                $type.type = self.resolve-type($type.type);
                $type.args .= map({ self.resolve-type($_) });
            }
            when GraphQL::InputValue
            {
                $type.type = self.resolve-type($type.type);
            }
        }
        return $type;
    }

    method resolve-schema
    {
        die "Must define root query type" unless self.queryType()
            and self.queryType.kind ~~ 'OBJECT';

        $!mutation //= 'Mutation' if self.type('Mutation');

        self!add-meta-fields;

        for %!types.values -> $type
        {
            self.resolve-type($type);
        }
    }

    method types { %!types.values }

    method add-type(*@newtypes)
    {
        for @newtypes
        {
            when GraphQL::Type { %!types{$_.name} = $_; }

            when GraphQL::InputObject { self.add-inputobject($_) }

            when Enumeration { self.add-enum($_) }

            default { self.add-class($_) }
        }
    }

    method maketype(Str $rule, Str $desc) returns GraphQL::Type
    {
        my $actions = GraphQL::Actions.new(:schema(self));

        GraphQL::Grammar.parse($desc, :$rule, :$actions).made;
    }

    method add-class($t)
    {
        my @fields;

        for $t.^attributes -> $a
        {
            next unless $a.has_accessor;

            my $var = $a ~~ /<-[!]>+$/;

            my $name = $var.Str;

            die "Invalid characters in $name"
                unless $name ~~ /^<[_A..Za..z]><[_0..9A..Za..z]>*$/;

            my $type = self.perl-type($a.type);

            push @fields, GraphQL::Field.new(:$name, :$type);
        }

        for $t.^methods -> $m
        {
            next if @fields.first: { $m.name eq $_.name };

            die "Invalid characters in $m.name()"
                unless $m.name ~~ /^<[_A..Za..z]><[_0..9A..Za..z]>*$/;

            my GraphQL::InputValue @args;

            my $sig = $m.signature;

            my $type = self.perl-type($sig.returns);

            for $sig.params -> $p
            {
                next unless $p.named;

                my $name = $p.named_names[0] or next;

                die "Invalid characters in $name"
                    unless $name ~~ /^<[_A..Za..z]><[_0..9A..Za..z]>*$/;

                my $type = self.perl-type($p.type);

                push @args, GraphQL::InputValue.new(:$name, :$type);
            }

            push @fields, GraphQL::Field.new(:name($m.name),
                                             :$type,
                                             :@args,
                                             :resolver($m));
        }

        self.add-type(GraphQL::Object.new(name => $t.^name,
                                          fieldlist => @fields));
    }

    method add-inputobject($t)
    {
        my @inputfields;

        for $t.^attributes -> $a
        {
            my $var = $a ~~ /<-[!]>+$/;
            my $name = $var.Str;

            my $type = self.perl-type($a.type);

            push @inputfields, GraphQL::InputValue.new(:$name, :$type);
        }

        self.add-type(GraphQL::InputObjectType.new(name => $t.^name,
                                                   inputFields => @inputfields,
                                                   class => $t));
    }

    method add-enum(Enumeration $t)
    {
        self.add-type(GraphQL::Enum.new(
                          name => $t.^name,
                          enumValues => $t.enums.map({
                              GraphQL::EnumValue.new(name => $_.key)
                          })
                      ));
    }

    method type($name) returns GraphQL::Type
    {
        %!types{$name} // GraphQL::LazyType.new(:$name);
    }

    method perl-type($type) returns GraphQL::Type
    {
        do given $type
        {
            when Enumeration { self.type($_.^name) }

            when Positional
            {
                GraphQL::List.new(ofType => self.perl-type($type.of));
            }

            when Bool   { $GraphQLBoolean }
            when Str    { $GraphQLString  }
            when Int    { $GraphQLInt     }
            when Num    { $GraphQLFloat   }
            when Cool   { $GraphQLID      }

            default
            {
                self.type($_.^name);
            }
        }
    }

    method queryType returns GraphQL::Object
    {
        return  ($!query and %!types{$!query}:exists and
                            %!types{$!query} ~~ GraphQL::Object)
            ?? %!types{$!query}
            !! Nil;
    }

    method mutationType returns GraphQL::Object
    {
        return unless $!mutation and %!types{$!mutation};
        %!types{$!mutation}
    }

    method subscriptionType returns GraphQL::Object
    {
        return unless $!subscription and %!types{$!subscription};
        %!types{$!subscription}
    }

    method directives { [] }

    method Str
    {
        self.resolve-schema;

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
        my $actions = GraphQL::Actions.new(:schema(self));

        GraphQL::Grammar.parse($query, :$actions,
                               rule => 'Document')
            or die "Failed to parse query";
        
        $/.made;
    }

    method resolvers(%resolvers)
    {
        for %resolvers.kv -> $type, $obj
        {
            die "Undefined object $type" unless %!types{$type};

            for $obj.kv -> $field, $resolver
            {
                die "Undefined field $field for $type"
                    unless %!types{$type}.field($field);
                    
                %!types{$type}.field($field).resolver = $resolver;
            }
        }
    }

    method error(:$message)
    {
        push @!errors, GraphQL::Error.new(:$message);
    }

    has $!resolved-schema;

    # ExecuteRequest() == $schema.execute()
    method execute(Str $query?,
                   GraphQL::Document :document($doc),
                   Str :$operationName,
                   :%variables,
                   :$initialValue)
    {
        self.resolve-schema unless $!resolved-schema++;

        @!errors = ();

        my $ret;

        try
        {
            my $document = $doc // self.document($query);

            my $operation = $document.GetOperation($operationName);

            my $selectionSet = $operation.selectionset;

            my %coercedVariableValues = CoerceVariableValues(:$operation,
                                                             :%variables);

            my $objectValue = $initialValue // 0;

            my $objectType = $operation.operation eq 'mutation'
                             ?? $.mutationType !! $.queryType;

            $ret = self.ExecuteSelectionSet(:$selectionSet,
                                            :$objectType,
                                            :$objectValue,
                                            :%variables,
                                            :$document);
            CATCH {
                default {
                    self.error(message => $_.Str);
                }
            }
        }

        my @response;

        if $ret
        {
            push @response, GraphQL::Response.new(
                name => 'data',
                type => GraphQL::Object,
                value => $ret
            );
        }

        if @!errors
        {
            push @response, GraphQL::Response.new(
                name => 'errors',
                type => GraphQL::List.new(ofType => GraphQL::Object),
                value => @!errors
            );
        }

        return GraphQL::Response.new(
            type => GraphQL::Object,
            value => @response
        );
    }

    method ExecuteSelectionSet(:@selectionSet,
                               GraphQL::Object :$objectType,
                               :$objectValue! is rw,
                               :%variables,
                               GraphQL::Document :$document)
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

            my $fieldType;

            if ($fieldName eq '__typename')
            {
                $responseValue = $objectType.name;
                $fieldType = $GraphQLString;
            }
            else
            {
                $fieldType = $objectType.field($fieldName).type
                    or die qq{Cannot query field '$fieldName' } ~
                           qq{on type '$objectType.name()'.};

                $responseValue = self.ExecuteField(:$objectType, 
                                                   :$objectValue,
                                                   :@fields,
                                                   :$fieldType,
                                                   :%variables,
                                                   :$document);
            }

            push @results, GraphQL::Response.new(
                               name => $responseKey,
                               type => $fieldType,
                               value => $responseValue);
        }

        return @results;
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

        if $resolvedValue ~~ Promise
        {
            return $resolvedValue.then(
                {
                    self.CompleteValue(:$fieldType,
                                       :@fields,
                                       :result($resolvedValue.result),
                                       :%variables,
                                       :$document)
                });
        }
        else
        {
            return self.CompleteValue(:$fieldType,
                                      :@fields,
                                      :result($resolvedValue),
                                      :%variables,
                                      :$document);
        }
    }

    method CompleteValue(GraphQL::Type :$fieldType,
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
                
                my $list = $result.map({ self.CompleteValue(
                                         :fieldType($fieldType.ofType),
                                         :@fields,
                                         :result($_),
                                         :%variables,
                                         :$document) });
                return $list;
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

sub CoerceArgumentValues(GraphQL::Object :$objectType,
                         GraphQL::QueryField :$field,
                         :%variables)
{
    my %coercedValues;

    for $objectType.field($field.name).args -> $arg
    {
        my $value = $field.args{$arg.name};

        if $value ~~ GraphQL::Variable and %variables{$value.name}:exists
        {
            $value = %variables{$value.name};
        }

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
                    next if %variables{$_.name} eq 'true';
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
                      :%argumentValues)
{
    my $field = $objectType.field($fieldName) or return;

    if $field.resolver ~~ Sub
    {
        $field.resolver.(|ResolveArgs($field.resolver.signature,
                                      :$objectValue,
                                      |%argumentValues));
    }
    elsif $objectValue.^lookup($fieldName) -> $method
    {
        $objectValue."$fieldName"(|ResolveArgs($method.signature,
                                               :$objectValue,
                                               |%argumentValues))
    }
    elsif $field.resolver ~~ Method
    {
        if $field.resolver ∈ $background-methods
        {
            start $field.resolver.package."$fieldName"(
                |ResolveArgs($field.resolver.signature,
                             :$objectValue,
                             |%argumentValues))
        }
        else
        {
            $field.resolver.package."$fieldName"(
                |ResolveArgs($field.resolver.signature,
                             :$objectValue,
                             |%argumentValues))
        }
    }
}

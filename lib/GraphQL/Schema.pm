unit module GraphQL::Schema;

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

    multi method new(:$queryType, :$mutationType, *@types)
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

        return $schema;
    }

    multi method new(Str $schemastring)
    {
        my $schema = GraphQL::Schema.new;
        
        my $actions = GraphQL::Actions.new(:$schema);

        GraphQL::Grammar.parse($schemastring, :$actions, :rule('TypeSchema'))
            or die "Failed to parse schema";

        $schema!add-meta-fields;

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

    method mutationType returns GraphQL::Object { %!types{$!mutation} }

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
}

use Bailador;
use GraphQL;
use GraphQL::GraphiQL;

use JSON::Fast;

class User
{
    has Int $.id is rw;
    has Str $.name is rw;
    has Str $.birthday is rw;
    has Bool $.status is rw;
}

my @users =
    User.new(id => 0,
             name => 'Gilligan',
             birthday => 'Friday',
             status => True),
    User.new(id => 1,
             name => 'Skipper',
             birthday => 'Monday',
             status => False),
    User.new(id => 2,
             name => 'Professor',
             birthday => 'Tuesday',
             status => True),
    User.new(id => 3,
             name => 'Ginger',
             birthday => 'Wednesday',
             status => True),
    User.new(id => 4,
             name => 'Mary Anne',
             birthday => 'Thursday',
             status => True);

my $resolvers = 
{
    Query =>
    {
        listusers => sub (:$start, Int :$count)
        {
            @users[$start ..^ $start+$count]
        },

        user => sub (:$id)
        {
            @users[$id]
        }
    },
    Mutation =>
    {
        adduser => sub (:%newuser)
        {
            push @users, User.new(id => @users.elems, |%newuser);
            return @users.elems - 1;
        },

        updateuser => sub (:$id, :%userinput)
        {
            for %userinput.kv -> $k, $v
            {
                @users[$id]."$k"() = $v;
            }

            @users[$id]
        }
    }
};

my $schema = GraphQL::Schema.new("users.schema".IO.slurp,
                                 resolvers => $resolvers);

get '/graphql' => sub { $GraphiQL }

post '/graphql' => sub {
    to-json($schema.execute(from-json(request.body)<query>));
}

baile;

package DBIx::Class::Schema::Loader::Base;

use strict;
use warnings;
use base qw/Class::Accessor::Fast/;
use Class::C3;
use Carp;
use UNIVERSAL::require;
use DBIx::Class::Schema::Loader::RelBuilder;
require DBIx::Class;

# The first group are all arguments which are may be defaulted within,
# The last two (classes, monikers) are generated locally:

__PACKAGE__->mk_ro_accessors(qw/
                                schema
                                exclude
                                constraint
                                additional_classes
                                additional_base_classes
                                left_base_classes
                                components
                                resultset_components
                                relationships
                                inflect_map
                                moniker_map
                                db_schema
                                debug

                                classes
                                monikers
                             /);

=head1 NAME

DBIx::Class::Schema::Loader::Base - Base DBIx::Class::Schema::Loader Implementation.

=head1 SYNOPSIS

See L<DBIx::Class::Schema::Loader>

=head1 DESCRIPTION

This is the base class for the vendor-specific C<DBIx::Class::Schema::*>
classes, and implements the common functionality between them.

=head1 OPTIONS

Available constructor options are:

=head2 additional_base_classes

List of additional base classes your table classes will use.

=head2 left_base_classes

List of additional base classes, that need to be leftmost.

=head2 additional_classes

List of additional classes which your table classes will use.

=head2 components

List of additional components to be loaded into your table classes.
A good example would be C<ResultSetManager>.

=head2 resultset_components

List of additional resultset components to be loaded into your table
classes.  A good example would be C<AlwaysRS>.  Component
C<ResultSetManager> will be automatically added to the above
C<components> list if this option is set.

=head2 constraint

Only load tables matching regex.

=head2 exclude

Exclude tables matching regex.

=head2 debug

Enable debug messages.

=head2 relationships

Try to automatically detect/setup has_a and has_many relationships.

=head2 moniker_map

Overrides the default tablename -> moniker translation.  Can be either
a hashref of table => moniker names, or a coderef for a translator
function taking a single scalar table name argument and returning
a scalar moniker.  If the hash entry does not exist, or the function
returns a false/undef value, the code falls back to default behavior
for that table name.

=head2 inflect_map

Just like L</moniker_map> above, but for inflecting (pluralizing)
relationship names.

=head2 inflect

Deprecated.  Equivalent to L</inflect_map>, but previously only took
a hashref argument, not a coderef.  If you set C<inflect> to anything,
that setting will be copied to L</inflect_map>.

=head2 connect_info

DEPRECATED, just use C<__PACKAGE__->connection()> instead, like you would
with any other L<DBIx::Class::Schema> (see those docs for details).
Similarly, if you wish to use a non-default storage_type, use
C<__PACKAGE__->storage_type()>.

=head2 dsn

DEPRECATED, see above...

=head2 user

DEPRECATED, see above...

=head2 password

DEPRECATED, see above...

=head2 options

DEPRECATED, see above...

=head1 METHODS

=cut

# ensure that a peice of object data is a valid arrayref, creating
# an empty one or encapsulating whatever's there.
sub _ensure_arrayref {
    my $self = shift;

    foreach (@_) {
        $self->{$_} ||= [];
        $self->{$_} = [ $self->{$_} ]
            unless ref $self->{$_} eq 'ARRAY';
    }
}

=head2 new

Constructor for L<DBIx::Class::Schema::Loader::Base>, used internally
by L<DBIx::Class::Schema::Loader>.

=cut

sub new {
    my ( $class, %args ) = @_;

    my $self = { %args };

    bless $self => $class;

    $self->{db_schema}  ||= '';
    $self->{constraint} ||= '.*';
    $self->_ensure_arrayref(qw/additional_classes
                               additional_base_classes
                               left_base_classes
                               components
                               resultset_components
                              /);

    push(@{$self->{components}}, 'ResultSetManager')
        if @{$self->{resultset_components}};

    $self->{monikers} = {};
    $self->{classes} = {};

    # Support deprecated argument name
    $self->{inflect_map} ||= $self->{inflect};

    $self;
}

sub _load_external {
    my $self = shift;

    foreach my $table_class (values %{$self->classes}) {
        $table_class->require;
        if($@ && $@ !~ /^Can't locate /) {
            croak "Failed to load external class definition"
                  . "for '$table_class': $@";
        }
        elsif(!$@) {
            warn qq/# Loaded external class definition for '$table_class'\n/
                if $self->debug;
        }
    }
}

=head2 load

Does the actual schema-construction work, used internally by
L<DBIx::Class::Schema::Loader> right after object construction.

=cut

sub load {
    my $self = shift;

    warn qq/\### START DBIx::Class::Schema::Loader dump ###\n/
        if $self->debug;

    $self->_load_classes;
    $self->_load_relationships if $self->relationships;
    $self->_load_external;

    warn qq/\### END DBIx::Class::Schema::Loader dump ###\n/
        if $self->debug;

    $self->schema->storage->disconnect;

    $self;
}

sub _use {
    my $self = shift;
    my $target = shift;

    foreach (@_) {
        $_->require or croak ($_ . "->require: $@");
        eval "package $target; use $_;";
        croak "use $_: $@" if $@;
    }
}

sub _inject {
    my $self = shift;
    my $target = shift;
    my $schema = $self->schema;

    foreach (@_) {
        $_->require or croak ($_ . "->require: $@");
        $schema->inject_base($target, $_);
    }
}

# Load and setup classes
sub _load_classes {
    my $self = shift;

    my $schema     = $self->schema;

    foreach my $table (sort $self->_tables_list) {
        my $constraint = $self->constraint;
        my $exclude = $self->exclude;

        next unless $table =~ /$constraint/;
        next if defined $exclude && $table =~ /$exclude/;

        my $table_moniker = $self->_table2moniker($table);
        my $table_class = $schema . q{::} . $table_moniker;

        { no strict 'refs';
          @{"${table_class}::ISA"} = qw/DBIx::Class/;
        }
        $self->_use   ($table_class, @{$self->additional_classes});
        $self->_inject($table_class, @{$self->additional_base_classes});
        $table_class->load_components(@{$self->components}, qw/PK::Auto Core/);
        $table_class->load_resultset_components(@{$self->resultset_components})
            if @{$self->resultset_components};
        $self->_inject($table_class, @{$self->left_base_classes});

        warn qq/$table_class->table('$table');\n/ if $self->debug;
        $table_class->table($table);

        my %cols_info = $self->_table_columns_info($table);
        if($self->debug) {
            my $cols_printable = '';
            foreach my $col (keys %cols_info) {
               my $cinfo = $cols_info{$col};
               my $hstr = '';
               foreach my $info (keys %$cinfo) {
                   $hstr .= "\n        $info => '" . $cinfo->{$info} . "', ";
               }
               $cols_printable .= "\n    $col => { $hstr\n    },";
            }
            warn qq/$table_class->add_columns(/
               . $cols_printable . qq/\n);\n/;
        }
        $table_class->add_columns(%cols_info);

        my $pks = $self->_table_pk_info($table) || [];
        if(@$pks) {
            warn qq/$table_class->set_primary_key(/
               . join(q{,}, map { "'$_'" } @$pks)
               . qq/);\n/ if $self->debug;
            $table_class->set_primary_key(@$pks);
        }
        else {
            carp("$table has no primary key");
        }

        # XXX need uniqs debug dump, and really need to clean
        #  up all of these with a Dumper-like thing
        my $uniqs = $self->_table_uniq_info($table) || [];
        foreach my $uniq (@$uniqs) {
            $table_class->add_unique_constraint( %$uniq );
        }

        $schema->register_class($table_moniker, $table_class);
        $self->classes->{$table} = $table_class;
        $self->monikers->{$table} = $table_moniker;
    }
}

=head2 tables

Returns a sorted list of loaded tables, using the original database table
names.  Actually generated from the keys of the C<monikers> hash below.

  my @tables = $schema->loader->tables;

=cut

sub tables {
    my $self = shift;

    return sort keys %{ $self->monikers };
}

# Make a moniker from a table
sub _table2moniker {
    my ( $self, $table ) = @_;

    my $moniker;

    if( ref $self->moniker_map eq 'HASH' ) {
        $moniker = $self->moniker_map->{$table};
    }
    elsif( ref $self->moniker_map eq 'CODE' ) {
        $moniker = $self->moniker_map->($table);
    }

    $moniker ||= join '', map ucfirst, split /[\W_]+/, lc $table;

    return $moniker;
}

sub _load_relationships {
    my $self = shift;

    # Construct the fk_info RelBuilder wants to see, by
    # translating table names to monikers in the _fk_info output
    my %fk_info;
    foreach my $table ($self->tables) {
        my $tbl_fk_info = $self->_table_fk_info($table);
        foreach my $fkdef (@$tbl_fk_info) {
            $fkdef->{remote_source} =
                $self->monikers->{delete $fkdef->{remote_table}};
        }
        my $moniker = $self->monikers->{$table};
        $fk_info{$moniker} = $tbl_fk_info;
    }

    # Let RelBuilder take over from here
    my $relbuilder = DBIx::Class::Schema::Loader::RelBuilder->new(
        $self->schema, \%fk_info, $self->inflect_map
    );
    $relbuilder->setup_rels($self->debug);
}

# Overload these in driver class:

# Returns an array ( col1name => { is_nullable => 1 }, ... )
sub _table_columns_info { croak "ABSTRACT METHOD" }

# Returns arrayref of pk col names
sub _table_pk_info { croak "ABSTRACT METHOD" }

# Returns an arrayref of uniqs [ { foo => [ col1, col2 ] }, { bar => [ ... ] } ]
sub _table_uniq_info { croak "ABSTRACT METHOD" }

# Returns an arrayref of foreign key constraints, each
#   being a hashref with 3 keys:
#   local_columns (arrayref), remote_columns (arrayref), remote_table
sub _table_fk_info { croak "ABSTRACT METHOD" }

# Returns an array of lower case table names
sub _tables_list { croak "ABSTRACT METHOD" }

=head2 monikers

Returns a hashref of loaded table-to-moniker mappings for the original
database table names.

  my $monikers = $schema->loader->monikers;
  my $foo_tbl_moniker = $monikers->{foo_tbl};
  # -or-
  my $foo_tbl_moniker = $schema->loader->monikers->{foo_tbl};
  # $foo_tbl_moniker would look like "FooTbl"

=head2 classes

Returns a hashref of table-to-classname mappings for the original database
table names.  You probably shouldn't be using this for any normal or simple
usage of your Schema.  The usual way to run queries on your tables is via
C<$schema-E<gt>resultset('FooTbl')>, where C<FooTbl> is a moniker as
returned by C<monikers> above.

  my $classes = $schema->loader->classes;
  my $foo_tbl_class = $classes->{foo_tbl};
  # -or-
  my $foo_tbl_class = $schema->loader->classes->{foo_tbl};
  # $foo_tbl_class would look like "My::Schema::FooTbl",
  #   assuming the schema class is "My::Schema"

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>

=cut

1;

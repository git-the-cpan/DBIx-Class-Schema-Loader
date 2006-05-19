package DBIx::Class::Schema::Loader::Base;

use strict;
use warnings;
use base qw/Class::Accessor::Fast/;
use Class::C3;
use Carp;
use UNIVERSAL::require;
use DBIx::Class::Schema::Loader::RelBuilder;
use Data::Dump qw/ dump /;
require DBIx::Class;

__PACKAGE__->mk_ro_accessors(qw/
                                schema
                                schema_class

                                exclude
                                constraint
                                additional_classes
                                additional_base_classes
                                left_base_classes
                                components
                                resultset_components
                                relationships
                                moniker_map
                                inflect_singular
                                inflect_plural
                                debug
                                dump_directory

                                legacy_default_inflections

                                db_schema
                                _tables
                                classes
                                monikers
                             /);

=head1 NAME

DBIx::Class::Schema::Loader::Base - Base DBIx::Class::Schema::Loader Implementation.

=head1 SYNOPSIS

See L<DBIx::Class::Schema::Loader>

=head1 DESCRIPTION

This is the base class for the storage-specific C<DBIx::Class::Schema::*>
classes, and implements the common functionality between them.

=head1 CONSTRUCTOR OPTIONS

These constructor options are the base options for
L<DBIx::Class::Schema::Loader/loader_opts>.  Available constructor options are:

=head2 relationships

Try to automatically detect/setup has_a and has_many relationships.

=head2 debug

Dump information about the created schema classes to stderr.

=head2 dump_directory

If this option is set, it will be treated as a perl libdir, and within
that directory this module will create a baseline manual
L<DBIx::Class::Schema> module set in that directory, based on what it
normally creates at runtime in memory, very similar to the C<debug> output.
The directory must already exist, and it would be wise to examine the output
before manually copying this over into your real libdirs.  As a precaution,
this will *not* overwrite any existing files (it will prefer to C<die>
in that case).

=head2 constraint

Only load tables matching regex.  Best specified as a qr// regex.

=head2 exclude

Exclude tables matching regex.  Best specified as a qr// regex.

=head2 moniker_map

Overrides the default tablename -> moniker translation.  Can be either
a hashref of table => moniker names, or a coderef for a translator
function taking a single scalar table name argument and returning
a scalar moniker.  If the hash entry does not exist, or the function
returns a false value, the code falls back to default behavior
for that table name.

The default behavior is: C<join '', map ucfirst, split /[\W_]+/, lc $table>,
which is to say: lowercase everything, split up the table name into chunks
anywhere a non-alpha-numeric character occurs, change the case of first letter
of each chunk to upper case, and put the chunks back together.  Examples:

    Table Name  | Moniker Name
    ---------------------------
    luser       | Luser
    luser_group | LuserGroup
    luser-opts  | LuserOpts

=head2 inflect_plural

Just like L</moniker_map> above (can be hash/code-ref, falls back to default
if hash key does not exist or coderef returns false), but acts as a map
for pluralizing relationship names.  The default behavior is to utilize
L<Lingua::EN::Inflect::Number/to_PL>.

=head2 inflect_singular

As L</inflect_plural> above, but for singularizing relationship names.
Default behavior is to utilize L<Lingua::EN::Inflect::Number/to_S>.

=head2 additional_base_classes

List of additional base classes all of your table classes will use.

=head2 left_base_classes

List of additional base classes all of your table classes will use
that need to be leftmost.

=head2 additional_classes

List of additional classes which all of your table classes will use.

=head2 components

List of additional components to be loaded into all of your table
classes.  A good example would be C<ResultSetManager>.

=head2 resultset_components

List of additional resultset components to be loaded into your table
classes.  A good example would be C<AlwaysRS>.  Component
C<ResultSetManager> will be automatically added to the above
C<components> list if this option is set.

=head2 legacy_default_inflections

Setting this option changes the default fallback for L</inflect_plural> to
utilize L<Lingua::EN::Inflect/PL>, and L</inflect_singlular> to a no-op.
Those choices produce substandard results, but might be neccesary to support
your existing code if you started developing on a version prior to 0.03 and
don't wish to go around updating all your relationship names to the new
defaults.

=head1 DEPRECATED CONSTRUCTOR OPTIONS

=head2 inflect_map

Equivalent to L</inflect_plural>.

=head2 inflect

Equivalent to L</inflect_plural>.

=head2 connect_info, dsn, user, password, options

You connect these schemas the same way you would any L<DBIx::Class::Schema>,
which is by calling either C<connect> or C<connection> on a schema class
or object.  These options are only supported via the deprecated
C<load_from_connection> interface, which will be removed in the future.

=head1 METHODS

None of these methods are intended for direct invocation by regular
users of L<DBIx::Class::Schema::Loader>.  Anything you can find here
can also be found via standard L<DBIx::Class::Schema> methods somehow.

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

    # Support deprecated arguments
    for(qw/inflect_map inflect/) {
        warn "Argument $_ is deprecated in favor of 'inflect_plural'"
            if $self->{$_};
    }
    $self->{inflect_plural} ||= $self->{inflect_map} || $self->{inflect};

    $self->{schema_class} = ref $self->{schema} || $self->{schema};

    $self;
}

sub _load_external {
    my $self = shift;

    foreach my $table_class (values %{$self->classes}) {
        $table_class->require;
        if($@ && $@ !~ /^Can't locate /) {
            croak "Failed to load external class definition"
                  . " for '$table_class': $@";
        }
        elsif(!$@) {
            warn qq/# Loaded external class definition for '$table_class'\n/
                if $self->debug;
        }
    }
}

=head2 load

Does the actual schema-construction work.

=cut

sub load {
    my $self = shift;

    $self->_load_classes;
    $self->_load_relationships if $self->relationships;
    $self->_load_external;

    if($self->dump_directory) {
        warn qq/\### XXX NOT IMPLEMENTED YET (dump directory) ###\n/;
    }
    elsif($self->debug) {
        my $schema_class = $self->schema_class;
        warn qq|\### DEBUG OUTPUT:\n\n|;
        warn qq|package $schema_class;\n\nuse strict;\nuse warnings;\n\n|;
        warn qq|use base 'DBIx::Class::Schema';\n\n|;
        warn qq|__PACKAGE__->load_classes;\n|;
        warn qq|\n1;\n\n|;
        foreach my $source (sort keys %{$self->{_debug_storage}}) {
            warn qq|package $source;\n\nuse strict;\nuse warnings;\n\n|;
            warn qq|use base 'DBIx::Class';\n\n|;
            warn qq|\__PACKAGE__->$_\n| for @{$self->{_debug_storage}->{$source}};
            warn qq|\n1;\n\n|;
        }
    }

    1;
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
    my $schema_class = $self->schema_class;

    foreach (@_) {
        $_->require or croak ($_ . "->require: $@");
        $schema_class->inject_base($target, $_);
    }
}

# Load and setup classes
sub _load_classes {
    my $self = shift;

    my $schema_class     = $self->schema_class;

    my $constraint = $self->constraint;
    my $exclude = $self->exclude;
    my @tables = sort $self->_tables_list;

    warn "No tables found in database, nothing to load" if !@tables;

    if(@tables) {
        @tables = grep { /$constraint/ } @tables if $constraint;
        @tables = grep { ! /$exclude/ } @tables if $exclude;

        warn "All tables excluded by constraint/exclude, nothing to load"
            if !@tables;
    }

    $self->{_tables} = \@tables;

    foreach my $table (@tables) {
        my $table_moniker = $self->_table2moniker($table);
        my $table_class = $schema_class . q{::} . $table_moniker;

        my $table_normalized = lc $table;
        $self->classes->{$table} = $table_class;
        $self->classes->{$table_normalized} = $table_class;
        $self->monikers->{$table} = $table_moniker;
        $self->monikers->{$table_normalized} = $table_moniker;

        no warnings 'redefine';
        local *Class::C3::reinitialize = sub { };
        use warnings;

        { no strict 'refs';
          @{"${table_class}::ISA"} = qw/DBIx::Class/;
        }
        $self->_use   ($table_class, @{$self->additional_classes});
        $self->_inject($table_class, @{$self->additional_base_classes});
        $table_class->load_components(@{$self->components}, qw/PK::Auto Core/);
        $table_class->load_resultset_components(@{$self->resultset_components})
            if @{$self->resultset_components};
        $self->_inject($table_class, @{$self->left_base_classes});
    }

    Class::C3::reinitialize;

    foreach my $table (@tables) {
        my $table_class = $self->classes->{$table};
        my $table_moniker = $self->monikers->{$table};

        $table_class->table($table);
        $self->_debug_store($table_class,'table',$table);

        my $cols = $self->_table_columns($table);
        $table_class->add_columns(@$cols);
        $self->_debug_store($table_class,'add_columns',@$cols);

        my $pks = $self->_table_pk_info($table) || [];
        if(@$pks) {
            $table_class->set_primary_key(@$pks);
            $self->_debug_store($table_class,'set_primary_key',@$pks);
        }
        else {
            carp("$table has no primary key");
        }

        my $uniqs = $self->_table_uniq_info($table) || [];
        foreach my $uniq (@$uniqs) {
            $table_class->add_unique_constraint( @$uniq );
            $self->_debug_store($table_class,'add_unique_constraint',@$uniq);
        }

        $schema_class->register_class($table_moniker, $table_class);
    }
}

=head2 tables

Returns a sorted list of loaded tables, using the original database table
names.

=cut

sub tables {
    my $self = shift;

    return @{$self->_tables};
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
        $self->schema_class, \%fk_info, $self->inflect_plural,
        $self->inflect_singular
    );
    $relbuilder->setup_rels($self->debug);
}

# Overload these in driver class:

# Returns an arrayref of column names
sub _table_columns { croak "ABSTRACT METHOD" }

# Returns arrayref of pk col names
sub _table_pk_info { croak "ABSTRACT METHOD" }

# Returns an arrayref of uniqs [ [ foo => [ col1, col2 ] ], [ bar => [ ... ] ] ]
sub _table_uniq_info { croak "ABSTRACT METHOD" }

# Returns an arrayref of foreign key constraints, each
#   being a hashref with 3 keys:
#   local_columns (arrayref), remote_columns (arrayref), remote_table
sub _table_fk_info { croak "ABSTRACT METHOD" }

# Returns an array of lower case table names
sub _tables_list { croak "ABSTRACT METHOD" }

sub _debug_store {
    my $self = shift;
    return if !$self->debug && !$self->dump_directory;

    my ($source, $method, @args) = @_;

    my $args = @args > 1
        ? dump(@args)
        : '(' . dump(@args) . ')';

    push(@{$self->{_debug_storage}->{$source}}, $method . $args);
}


=head2 monikers

Returns a hashref of loaded table-to-moniker mappings.  There will
be two entries for each table, the original name and the "normalized"
name, in the case that the two are different (such as databases
that like uppercase table names, or preserve your original mixed-case
definitions, or what-have-you).

=head2 classes

Returns a hashref of table-to-classname mappings.  In some cases it will
contain multiple entries per table for the original and normalized table
names, as above in L</monikers>.

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>

=cut

1;

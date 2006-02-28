package DBIx::Class::Schema::Loader::DBI;

use strict;
use warnings;
use base qw/DBIx::Class::Schema::Loader::Base Class::Accessor::Fast/;
use Class::C3;
use Carp;

=head1 NAME

DBIx::Class::Schema::Loader::DBI - DBIx::Class::Schema::Loader DBI Implementation.

=head1 SYNOPSIS

See L<DBIx::Class::Schema::Loader::Base>

=head1 DESCRIPTION

This is the base class for L<DBIx::Class::Schema::Loader> DBI-based storage
backends and implements the common functionality between them.

See L<DBIx::Class::Schema::Loader::Base> for the available options.

=head1 METHODS

=head2 new

Overlays L<DBIx::Class::Schema::Loader::Base/new> to add support for
deprecated connect_info and dsn/user/password/options args, and to
rebless into a vendor class if neccesary.

=cut

sub new {
    my $self = shift->next::method(@_);

    # Support deprecated connect_info and dsn args
    if($self->{connect_info}) {
        warn "Argument connect_info is deprecated";
        $self->schema->connection(@{$self->{connect_info}});
    }
    elsif($self->{dsn}) {
        warn "Arguments dsn, user, password, and options are deprecated";
        $self->schema->connection(
            $self->{dsn},
            $self->{user},
            $self->{password},
            $self->{options},
        );
    }

    # rebless to vendor-specific class if it exists and loads
    my $driver = $self->schema->storage->dbh->{Driver}->{Name};
    eval "require DBIx::Class::Schema::Loader::DBI::${driver}";
    unless ($@) {
        bless $self, "DBIx::Class::Schema::Loader::DBI::${driver}";
    }

    $self;
}

# Find and setup relationships
sub _load_relationships {
    my $self = shift;

    my $dbh = $self->schema->storage->dbh;
    my $quoter = $dbh->get_info(29) || q{"};
    foreach my $table ( $self->tables ) {
        my $rels = {};
        my $sth = $dbh->foreign_key_info( '',
            $self->db_schema, '', '', '', $table );
        next if !$sth;
        while(my $raw_rel = $sth->fetchrow_hashref) {
            my $uk_tbl  = lc $raw_rel->{UK_TABLE_NAME};
            my $uk_col  = lc $raw_rel->{UK_COLUMN_NAME};
            my $fk_col  = lc $raw_rel->{FK_COLUMN_NAME};
            my $relid   = lc $raw_rel->{UK_NAME};
            $uk_tbl =~ s/$quoter//g;
            $uk_col =~ s/$quoter//g;
            $fk_col =~ s/$quoter//g;
            $relid  =~ s/$quoter//g;
            $rels->{$relid}->{tbl} = $uk_tbl;
            $rels->{$relid}->{cols}->{$uk_col} = $fk_col;
        }

        foreach my $relid (keys %$rels) {
            my $reltbl = $rels->{$relid}->{tbl};
            my $cond   = $rels->{$relid}->{cols};
            eval { $self->_make_cond_rel( $table, $reltbl, $cond ) };
              warn qq/\# belongs_to_many failed "$@"\n\n/
                if $@ && $self->debug;
        }
    }
}

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>

=cut

1;

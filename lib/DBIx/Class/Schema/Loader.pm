package DBIx::Class::Schema::Loader;

use strict;
use warnings;
use base qw/DBIx::Class::Schema/;
use base qw/Class::Data::Accessor/;
use Carp;
use UNIVERSAL::require;
use Class::C3;

# Always remember to do all digits for the version even if they're 0
# i.e. first release of 0.XX *must* be 0.XX000. This avoids fBSD ports
# brain damage and presumably various other packaging systems too
our $VERSION = '0.02999_07';

__PACKAGE__->mk_classaccessor('loader');
__PACKAGE__->mk_classaccessor('_loader_args');
__PACKAGE__->mk_classaccessor('_loaded');

=head1 NAME

DBIx::Class::Schema::Loader - Dynamic definition of a DBIx::Class::Schema

=head1 SYNOPSIS

  package My::Schema;
  use base qw/DBIx::Class::Schema::Loader/;

  __PACKAGE__->loader_options(
      relationships           => 1,
      constraint              => '^foo.*',
      # debug                 => 1,
  );

  # in seperate application code ...

  use My::Schema;

  my $schema1 = My::Schema->connect( $dsn, $user, $password, $attrs);
  # -or-
  my $schema1 = "My::Schema"; $schema1->connection(as above);

=head1 DESCRIPTION

DBIx::Class::Schema::Loader automates the definition of a
DBIx::Class::Schema by scanning table schemas and setting up
columns and primary keys.

DBIx::Class::Schema::Loader supports MySQL, Postgres, SQLite and DB2.  See
L<DBIx::Class::Schema::Loader::Base> for more, and
L<DBIx::Class::Schema::Loader::Writing> for notes on writing your own
db-specific subclass for an unsupported db.

This module requires L<DBIx::Class> 0.05 or later, and obsoletes
L<DBIx::Class::Loader> for L<DBIx::Class> version 0.05 and later.

While on the whole, the bare table definitions are fairly straightforward,
relationship creation is somewhat heuristic, especially in the choosing
of relationship types, join types, and relationship names.  The relationships
generated by this module will probably never be as well-defined as
hand-generated ones.  Because of this, over time a complex project will
probably wish to migrate off of L<DBIx::Class::Schema::Loader>.

It is designed more to get you up and running quickly against an existing
database, or to be effective for simple situations, rather than to be what
you use in the long term for a complex database/project.

That being said, transitioning your code from a Schema generated by this
module to one that doesn't use this module should be straightforward and
painless, so don't shy away from it just for fears of the transition down
the road.

=head1 METHODS

=head2 loader_options

Example in Synopsis above demonstrates a few common arguments.  For
detailed information on all of the arguments, see the
L<DBIx::Class::Schema::Loader::Base> documentation.

This method is *required*, for backwards compatibility reasons.  If
you do not wish to change any options, just call it with an empty
argument list during schema class initialization.

=cut

sub loader_options {
    my ( $self, %args ) = @_;

    $args{schema} = ref $self || $self;
    $self->_loader_args(\%args);

    $self;
}

sub _invoke_loader {
    my $self = shift;

    # XXX this only works for relative storage_type, like ::DBI ...
    my $impl = "DBIx::Class::Schema::Loader" . $self->storage_type;
    $impl->require or
      croak qq/Could not load storage_type loader "$impl": / .
            qq/"$UNIVERSAL::require::ERROR"/;

    # XXX in the future when we get rid of ->loader, the next two
    # lines can be replaced by "$impl->new(%{$self->{_loader_args}})->load;"
    $self->loader($impl->new(%{$self->_loader_args}));
    $self->loader->load;

    my $class = ref $self || $self;
    $class->_loaded(1);

    $self;
}

=head2 connection

See L<DBIx::Class::Schema>.  Our local override here is to
hook in the main functionality of the loader, which occurs at the time
the connection is specified for a given schema class/object.

=cut

sub connection {
    my $self = shift;

    $self->next::method(@_);

    my $class = ref $self || $self;
    $self->_invoke_loader if $self->_loader_args && !$class->_loaded;

    $self;
}

=head2 clone

See L<DBIx::Class::Schema>.  Our local override here is to
make sure cloned schemas can still be loaded at runtime by
copying and altering a few things here.

=cut

sub clone {
    my $self = shift;

    my $clone = $self->next::method(@_);
    return $clone->_loader_args->{schema} = $clone;
}

=head1 EXAMPLE

Using the example in L<DBIx::Class::Manual::ExampleSchema> as a basis
replace the DB::Main with the following code:

  package DB::Main;

  use base qw/DBIx::Class::Schema::Loader/;

  __PACKAGE__->loader_options(
      relationships => 1,
      debug         => 1,
  );
  __PACKAGE__->connection('dbi:SQLite:example.db');

  1;

and remove the Main directory tree (optional).  Every thing else
should work the same

=head1 DEPRECATED METHODS

You don't need to read anything in this section unless you're upgrading
code that was written against pre-0.03 versions of this module.  This
version is intended to be backwards-compatible with pre-0.03 code, but
will issue warnings about your usage of deprecated features/methods.

=head2 load_from_connection

This deprecated method is now roughly an alias for L</loader_options>.

In the past it was a common idiom to invoke this method
after defining a connection on the schema class.  That usage is now
deprecated.  The correct way to do things from now forward is to
always do C<loader_options> on the class before C<connect> or
C<connection> is invoked on the class or any derived object.

This method *will* dissappear in a future version.

For now, using this method will invoke the legacy behavior for
backwards compatibility, and merely emit a warning about upgrading
your code.

It also reverts the default inflection scheme to
use L<Lingua::EN::Inflect> just like pre-0.03 versions of this
module did.

You can force these legacy inflections with the
option C<legacy_default_inflections>, even after switch over
to the preferred L</loader_options> way of doing things.

See the source of this method for more details.

=cut

sub load_from_connection {
    my ($self, %args) = @_;
    warn "load_from_connection deprecated, please (re-)read the"
      . "DBIx::Class::Schema::Loader documentation";

    # Support the old connect_info / dsn / etc args...
    $args{connect_info} = [
        delete $args{dsn},
        delete $args{user},
        delete $args{password},
        delete $args{options},
    ] if $args{dsn};

    $self->connection(@{delete $args{connect_info}})
        if $args{connect_info};

    $self->loader_options('legacy_default_inflections' => 1, %args);

    my $class = ref $self || $self;
    $self->_invoke_loader if $self->storage && !$class->_loaded;
}

=head2 loader

This is an accessor in the generated Schema class for accessing
the L<DBIx::Class::Schema::Loader::Base> -based loader object
that was used during construction.  See the
L<DBIx::Class::Schema::Loader::Base> docs for more information
on the available loader methods there.

This accessor is deprecated.  Do not use it.  Anything you can
get from C<loader>, you can get via the normal L<DBIx::Class::Schema>
methods, and your code will be more robust and forward-thinking
for doing so.

If you're already using C<loader> in your code, make an effort
to get rid of it.  If you think you've found a situation where it
is neccesary, let me know and we'll see what we can do to remedy
that situation.

In some future version, this accessor *will* disappear.  It was
apparently quite a design/API mistake to ever have exposed it to
user-land in the first place, all things considered.

=head1 KNOWN ISSUES

=head2 Multiple Database Schemas

Currently the loader is limited to working within a single schema
(using the database vendors' definition of "schema").  If you
have a multi-schema database with inter-schema relationships (which
is easy to do in Postgres or DB2 for instance), you only get to
automatically load the tables of one schema, and any relationships
to tables in other schemas will be silently ignored.

At some point in the future, an intelligent way around this might be
devised, probably by allowing the C<db_schema> option to be an
arrayref of schemas to load, or perhaps even offering schema
constraint/exclusion options just like the table ones.

In "normal" L<DBIx::Class::Schema> usage, manually-defined
source classes and relationships have no problems crossing vendor schemas.

=head1 AUTHOR

Brandon Black, C<blblack@gmail.com>

Based on L<DBIx::Class::Loader> by Sebastian Riedel

Based upon the work of IKEBE Tomohiro

=head1 THANK YOU

Adam Anderson, Andy Grundman, Autrijus Tang, Dan Kubb, David Naughton,
Randal Schwartz, Simon Flack, Matt S Trout, everyone on #dbix-class, and
all the others who've helped.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=head1 SEE ALSO

L<DBIx::Class>, L<DBIx::Class::Manual::ExampleSchema>

=cut

1;

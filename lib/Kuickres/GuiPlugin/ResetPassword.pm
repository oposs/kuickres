package Kuickres::GuiPlugin::ResetPassword;
use Mojo::Base 'CallBackery::GuiPlugin::AbstractForm', -signatures;
use CallBackery::Translate qw(trm);
use CallBackery::Exception qw(mkerror);
use Mojo::JSON qw(true false);
use Mojo::Util qw(dumper hmac_sha1_sum md5_sum);
use Time::Piece qw(localtime);
use POSIX qw(strftime);
use Email::MIME;
use Email::Sender::Simple;

=head1 NAME

Kuickres::GuiPlugin::ResetPassword - Reset Password

=head1 SYNOPSIS

 use Kuickres::GuiPlugin::ResetPassword;

=head1 DESCRIPTION

The Reset Password Form

=cut

has checkAccess => sub {
    1;
};

has mayAnonymous => sub {
    1;
};

=head1 METHODS

All the methods of L<CallBackery::GuiPlugin::AbstractForm> plus:

=cut

sub db {
    shift->user->mojoSqlDb;
}

=head2 formCfg

Returns a Configuration Structure for the Booking Entry Form.

=cut

has accountMustExist => 1;

has formCfg => sub {
    my $self = shift;
    my $args = $self->args // {};
    my $form = $args->{currentFormData} // {};

    my $emailCheck = sub ($email,$fieldName=undef,$form={}) {
        return trm("Invalid email address") 
            unless $email and $email =~ /^[^@\s]+@[^@\s]+$/;
        if (my $mailrx = $self->config->{mailrx}){
            return trm("Invalid email address")
                unless $email and $email =~ m/$mailrx/,
        }
        if ($self->accountMustExist) {
            return trm("Unknown email address")
                if not $self->db->select('cbuser',undef,{
                    cbuser_login => $email
                })->hash;
        }
        else {
            return trm("email address in use")
                if $self->db->select('cbuser',undef,{
                    cbuser_login => $email
                })->hash;
        }
        return;
    };

    my $tokenCheck = sub ($token,$fieldName=undef,$form={}) {
        return trm("Invalid token")
            unless $self->checkToken($form->{email},$token);
        return;
    };

    my $passwordCheck1 = sub ($value='',$fieldName=undef,$form={}) {
        chomp($value);
        my $len = length($value);
        return trm('Passwords must be 8 chars or longer')
            if $len < 8;
        return trm('Passwords < 20 chars must contain upper- and lowercase letters')
            if $len < 20 && not ($value =~ /[a-z]/ and $value =~ /[A-Z]/);
        return trm('Passwords < 16 chars must contain upper- and lowercase letters and numbers')
            if $len < 16 && not ($value =~ /[1-9]/);
        return trm('Passwords < 12 chars must contain upper- and lowercase letters and numbers and special characters')
            if $len < 12 && not ($value =~ /[^ A-Z1-9a-z]/);
        return;
    };
    my $passwordCheck2 = sub ($value,$fieldName=undef,$form={}) {        
        return trm('Passwords must must match')
            if $value ne $form->{pass1};
        return;
    };
    my $tokenSent = $emailCheck->($form->{email}) ? false : true;
    my $tokenOk = $tokenCheck->($form->{token},undef,$form) ? false : true;
    return [
        {
            key => 'email',
            label => trm('Email Address'),
            widget => 'text',
            triggerFormReset => true,
            validator => $emailCheck,
            actionSet => {
                sendToken => {
                    enabled => $tokenOk ? false : true,
                }
            },
            set => {
                nativeContextMenu => true,
                required => true,
                readOnly => $tokenOk,
            }
        },
        {
            key => 'token',
            label => trm('Validation Token'),
            widget => 'text',
            triggerFormReset => true,
            set => {
                readOnly => $tokenOk,
                placeholder => trm('check your mail for a token'),
                nativeContextMenu => true
            },
            validator => $tokenCheck,
            note => trm('[Send Token]'),
            actionSet => {
                setPassword => {
                    enabled => $tokenOk,
                }
            },
        },
        {
            key => 'pass1',
            label => trm('New Password'),
            widget => 'password',
            note => trm('<a target="_new" href="https://uit.stanford.edu/service/accounts/passwords/quickguide">Standford Password Policy</a>'),
            set => {
                placeholder => trm('type a your new password'),
                nativeContextMenu => true,
            },
            
            validator => $passwordCheck1,
        },
        {
            key => 'pass2',
            label => trm('Repeat Password'),
            widget => 'password',
            set => {
                placeholder => trm('repeat the password'),
                nativeContextMenu => true,
            },
            validator => $passwordCheck2,
        },
    ];
};

has createActionLabel => sub {
    trm('Set New Password');
};

sub createAction ($self,$args) {
    # now all is required ... 
    for (qw(email token pass1 pass2)){
        die mkerror(3893,trm('%1 is required',$_))
            unless $args->{$_};
    }
    eval {
        $self->db->update('cbuser',{
            cbuser_password => hmac_sha1_sum($args->{pass1})
        },{
            cbuser_login => $args->{email}
        });
    };
    if ($@) {
        $self->log->error($@);
        die mkerror(3884,
            trm("Failed to update password for %1",$args->{email}));
    }
    return {
        action => 'dataSaved'
    };
}

has actionCfg => sub {
    my $self = shift;
    my $type = $self->config->{type} // 'add';
    my $handler = 

    return [
         {
            label => trm('Send Token'),
            action => 'submit',
            key => 'sendToken',
            actionHandler => sub ($self,$args) {
                $self->sendTokenMail($args->{email});
                return {
                    action => 'showMessage',
                    title => trm('Token sent'),
                    message => trm('The token has been sent to your Mailbox.'),
                };
            }
        },
        {
            label => $self->createActionLabel,
            action => 'submit',
            key => 'setPassword',
            actionHandler => sub ($self,$args) {
                $self->createAction($args);
            }
        }
    ];
};

has grammar => sub {
    my $self = shift;
    $self->mergeGrammar(
        $self->SUPER::grammar,
        {
            _vars => [ qw(from subject mailrx) ],
            _mandatory => [ qw(from subject) ],
            from => {
                _doc => 'sender for mails',
            },
            subject => {
                _doc => 'subject for token mails',
            },
            mailrx => {
                _doc => 'regular expression reuired to match for emails',
            },
        },
    );
};

sub getAllFieldValues {
    my $self = shift;
    my $args = shift;
    return {};
}

sub getToken ($self,$email,$slot=sprintf("%x",int(time / 3600))) {
    return "no-token" unless $email;
    return $slot.'g'.md5_sum($email.$self->app->secrets->[0].$slot);
}

sub checkToken ($self,$email,$token) {
    return 0 unless $email and $token;
    my ($slot,$sum) = split /g/,$token,2;
    return $token eq $self->getToken($email,$slot);
}

sub tokenMail ($self,$email,$token) {
    return trm('Hallo %1,

Jemand versucht gerade ihr Passwort bei Kuickres neu zu setzen
falls sie das selber sind, tragen sie das untenstehende Token  

%2

im Passwort-Reset Fenster ein.',$email,$token);
}

sub sendTokenMail ($self,$email) {
    my $token = $self->getToken($email);
    eval {
        my $msg = Email::MIME->create(
            header_str => [
                To      => $email,
                From    => $self->config->{from},
                Subject => $self->config->{subject},
            ],
            body_str      => $self->tokenMail($email,$token),
            attributes  => {
                charset => 'UTF-8',
                encoding => 'quoted-printable',
                content_type => "text/plain",
            }
        );
        Email::Sender::Simple->send($msg);
    };
    if ($@) {
        $self->log->warn($@);
    }
}

1;
__END__

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=head1 HISTORY

 2020-03-16 oetiker 0.0 first version

=cut

####################################################################################################################################
# DOC EXECUTE MODULE
####################################################################################################################################
package BackRestDoc::Common::DocExecute;
use parent 'BackRestDoc::Common::DocRender';

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use Exporter qw(import);
    our @EXPORT = qw();
use File::Basename qw(dirname);
use Storable qw(dclone);

use lib dirname($0) . '/../lib';
use pgBackRest::Common::Ini;
use pgBackRest::Common::Log;
use pgBackRest::Common::String;
use pgBackRest::Config::Config;
use pgBackRest::FileCommon;
use pgBackRest::Version;

use lib dirname($0) . '/../test/lib';
use pgBackRestTest::Common::ExecuteTest;
use pgBackRestTest::Common::HostTest;

use BackRestDoc::Common::DocManifest;

####################################################################################################################################
# CONSTRUCTOR
####################################################################################################################################
sub new
{
    my $class = shift;       # Class name

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strType,
        $oManifest,
        $strRenderOutKey,
        $bExe
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->new', \@_,
            {name => 'strType'},
            {name => 'oManifest'},
            {name => 'strRenderOutKey'},
            {name => 'bExe'}
        );

    # Create the class hash
    my $self = $class->SUPER::new($strType, $oManifest, $strRenderOutKey);
    bless $self, $class;

    $self->{bExe} = $bExe;
    $self->{bCache} = false;
    $self->{iCacheIdx} = undef;

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'self', value => $self}
    );
}

####################################################################################################################################
# executeKey
#
# Get a unique key for the execution step to determine if the cache is valid.
####################################################################################################################################
sub executeKey
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strHostName,
        $oCommand,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->executeKey', \@_,
            {name => 'strHostName', trace => true},
            {name => 'oCommand', trace => true},
        );

    # Format and split command
    my $strCommand = trim($oCommand->fieldGet('exe-cmd'));
    $strCommand =~ s/[ ]*\n[ ]*/ \\\n    /smg;
    my @stryCommand = split("\n", $strCommand);

    my $hCacheKey =
    {
        host => $strHostName,
        user => $self->{oManifest}->variableReplace($oCommand->paramGet('user', false, 'postgres')),
        cmd => \@stryCommand,
    };

    if (defined($oCommand->paramGet('err-expect', false)))
    {
        $$hCacheKey{'err-expect'} = $oCommand->paramGet('err-expect');
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'hExecuteKey', value => $hCacheKey, trace => true}
    );
}

####################################################################################################################################
# execute
####################################################################################################################################
sub execute
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $oSection,
        $strHostName,
        $oCommand,
        $iIndent
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->execute', \@_,
            {name => 'oSection'},
            {name => 'strHostName'},
            {name => 'oCommand'},
            {name => 'iIndent', default => 1}
        );

    # Working variables
    my $strCommand;
    my $strOutput;

    my ($bCacheHit, $strCacheType, $hCacheKey, $hCacheValue) = $self->cachePop('exe', $self->executeKey($strHostName, $oCommand));

    if ($oCommand->fieldTest('actual-command'))
    {
        $strCommand = $oCommand->fieldGet('actual-command');
        $strOutput = $oCommand->fieldGet('actual-output', false);
    }
    else
    {
        # Command variables
        my $bExeOutput = $oCommand->paramTest('output', 'y');
        my $strVariableKey = $oCommand->paramGet('variable-key', false);

        # Create the cache entry
        my $hExecuteCache =
        {
            key => $hCacheKey,
            type => 'execute',
        };

        # Add user to run the command as
        $strCommand = $self->{oManifest}->variableReplace(
            ($$hCacheKey{user} eq 'vagrant' ? '' :
                ('sudo ' . ($$hCacheKey{user} eq 'root' ? '' : "-u $$hCacheKey{user} "))) . join("\n", @{$$hCacheKey{cmd}}));

        if (!$oCommand->paramTest('show', 'n') && $self->{bExe} && $self->isRequired($oSection))
        {
            # Make sure that no lines are greater than 80 chars
            foreach my $strLine (split("\n", $strCommand))
            {
                if (length(trim($strLine)) > 80)
                {
                    confess &log(ERROR, "command has a line > 80 characters:\n${strCommand}\noffending line: ${strLine}");
                }
            }
        }

        &log(DEBUG, ('    ' x $iIndent) . "execute: $strCommand");

        if (!$oCommand->paramTest('skip', 'y'))
        {
            if ($self->{bExe} && $self->isRequired($oSection))
            {
                # Check that the host is valid
                my $oHost = $self->{host}{$strHostName};

                if (!defined($oHost))
                {
                    confess &log(ERROR, "cannot execute on host ${strHostName} because the host does not exist");
                }

                $$hCacheValue{cmd} = $strCommand;

                my $oExec = $oHost->execute($strCommand,
                                            {iExpectedExitStatus => $$hCacheKey{'err-expect'},
                                             bSuppressError => $oCommand->paramTest('err-suppress', 'y'),
                                             iRetrySeconds => $oCommand->paramGet('retry', false)});
                $oExec->begin();
                $oExec->end();

                if ($bExeOutput && defined($oExec->{strOutLog}) && $oExec->{strOutLog} ne '')
                {
                    $strOutput = $oExec->{strOutLog};

                    # Trim off extra linefeeds before and after
                    $strOutput =~ s/^\n+|\n$//g;

                    if ($strCommand =~ / pgbackrest /)
                    {
                        $strOutput =~ s/^                             //smg;
                        $strOutput =~ s/^[0-9]{4}-[0-1][0-9]-[0-3][0-9] [0-2][0-9]:[0-6][0-9]:[0-6][0-9]\.[0-9]{3} T[0-9]{2} //smg;
                    }

                    my @stryOutput = split("\n", $strOutput);
                    $$hCacheValue{output} = \@stryOutput;
                }

                if (defined($$hCacheKey{'err-expect'}))
                {
                    $strOutput .= trim($oExec->{strErrorLog});
                }

                # Output is assigned to a var
                if (defined($strVariableKey))
                {
                    $self->{oManifest}->variableSet($strVariableKey, trim($oExec->{strOutLog}));
                }
                elsif (!$oCommand->paramTest('filter', 'n') && $bExeOutput && defined($strOutput))
                {
                    my $strHighLight = $self->{oManifest}->variableReplace($oCommand->fieldGet('exe-highlight', false));

                    if (!defined($strHighLight))
                    {
                        confess &log(ERROR, 'filter requires highlight definition: ' . $strCommand);
                    }

                    my $iFilterContext = $oCommand->paramGet('filter-context', false, 2);

                    my @stryOutput = split("\n", $strOutput);
                    undef($strOutput);
                    # my $iFiltered = 0;
                    my $iLastOutput = -1;

                    for (my $iIndex = 0; $iIndex < @stryOutput; $iIndex++)
                    {
                        if ($stryOutput[$iIndex] =~ /$strHighLight/)
                        {
                            # Determine the first line to output
                            my $iFilterFirst = $iIndex - $iFilterContext;

                            # Don't go past the beginning
                            $iFilterFirst = $iFilterFirst < 0 ? 0 : $iFilterFirst;

                            # Don't repeat lines that have already been output
                            $iFilterFirst  = $iFilterFirst <= $iLastOutput ? $iLastOutput + 1 : $iFilterFirst;

                            # Determine the last line to output
                            my $iFilterLast = $iIndex + $iFilterContext;

                            # Don't got past the end
                            $iFilterLast = $iFilterLast >= @stryOutput ? @stryOutput -1 : $iFilterLast;

                            # Mark filtered lines if any
                            if ($iFilterFirst > $iLastOutput + 1)
                            {
                                my $iFiltered = $iFilterFirst - ($iLastOutput + 1);

                                if ($iFiltered > 1)
                                {
                                    $strOutput .= (defined($strOutput) ? "\n" : '') .
                                                  "       [filtered ${iFiltered} lines of output]";
                                }
                                else
                                {
                                    $iFilterFirst -= 1;
                                }
                            }

                            # Output the lines
                            for (my $iOutputIndex = $iFilterFirst; $iOutputIndex <= $iFilterLast; $iOutputIndex++)
                            {
                                    $strOutput .= (defined($strOutput) ? "\n" : '') . $stryOutput[$iOutputIndex];
                            }

                            $iLastOutput = $iFilterLast;
                        }
                    }

                    if (@stryOutput - 1 > $iLastOutput + 1)
                    {
                        my $iFiltered = (@stryOutput - 1) - ($iLastOutput + 1);

                        if ($iFiltered > 1)
                        {
                            $strOutput .= (defined($strOutput) ? "\n" : '') .
                                          "       [filtered ${iFiltered} lines of output]";
                        }
                        else
                        {
                            $strOutput .= (defined($strOutput) ? "\n" : '') . $stryOutput[@stryOutput - 1];
                        }
                    }
                }
            }
            elsif ($bExeOutput)
            {
                $strOutput = 'Output suppressed for testing';
            }
        }

        if (defined($strVariableKey) && !defined($self->{oManifest}->variableGet($strVariableKey)))
        {
            $self->{oManifest}->variableSet($strVariableKey, '[Test Variable]');
        }

        $oCommand->fieldSet('actual-command', $strCommand);
        $oCommand->fieldSet('actual-output', $strOutput);

        $self->cachePush($strCacheType, $hCacheKey, $hCacheValue);
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strCommand', value => $strCommand, trace => true},
        {name => 'strOutput', value => $strOutput, trace => true}
    );
}


####################################################################################################################################
# configKey
####################################################################################################################################
sub configKey
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $oConfig,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->hostKey', \@_,
            {name => 'oConfig', trace => true},
        );

    my $hCacheKey =
    {
        host => $self->{oManifest}->variableReplace($oConfig->paramGet('host')),
        file => $oConfig->paramGet('file'),
    };

    if ($oConfig->paramTest('reset', 'y'))
    {
        $$hCacheKey{reset} = true;
    }

    # Add all options to the key
    my $strOptionTag = $oConfig->nameGet() eq 'backrest-config' ? 'backrest-config-option' : 'postgres-config-option';

    foreach my $oOption ($oConfig->nodeList($strOptionTag))
    {
        my $hOption = {};

        if ($oOption->paramTest('remove', 'y'))
        {
            $$hOption{remove} = true;
        }

        if (defined($oOption->valueGet(false)))
        {
            $$hOption{value} = $oOption->valueGet();
        }

        if ($oConfig->nameGet() eq 'backrest-config')
        {
            $$hCacheKey{option}{$oOption->paramGet('section')}{$oOption->paramGet('key')} = $hOption;
        }
        else
        {
            $$hCacheKey{option}{$oOption->paramGet('key')} = $hOption;
        }
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'hCacheKey', value => $hCacheKey, trace => true}
    );
}

####################################################################################################################################
# backrestConfig
####################################################################################################################################
sub backrestConfig
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $oSection,
        $oConfig,
        $iDepth
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->backrestConfig', \@_,
            {name => 'oSection'},
            {name => 'oConfig'},
            {name => 'iDepth'}
        );

    # Working variables
    my $strFile;
    my $strConfig;

    my ($bCacheHit, $strCacheType, $hCacheKey, $hCacheValue) = $self->cachePop('cfg-' . BACKREST_EXE, $self->configKey($oConfig));

    if ($oConfig->fieldTest('actual-file'))
    {
        $strFile = $oConfig->fieldGet('actual-file');
        $strConfig = $oConfig->fieldGet('actual-config');
    }
    else
    {
        # Get filename
        $strFile = $self->{oManifest}->variableReplace($oConfig->paramGet('file'));

        &log(DEBUG, ('    ' x $iDepth) . 'process backrest config: ' . $strFile);

        if ($self->{bExe} && $self->isRequired($oSection))
        {
            # Check that the host is valid
            my $strHostName = $self->{oManifest}->variableReplace($oConfig->paramGet('host'));
            my $oHost = $self->{host}{$strHostName};

            if (!defined($oHost))
            {
                confess &log(ERROR, "cannot configure backrest on host ${strHostName} because the host does not exist");
            }

            # Reset all options
            if ($oConfig->paramTest('reset', 'y'))
            {
                delete(${$self->{config}}{$strHostName}{$strFile})
            }

            foreach my $oOption ($oConfig->nodeList('backrest-config-option'))
            {
                my $strSection = $oOption->paramGet('section');
                my $strKey = $oOption->paramGet('key');
                my $strValue;

                if (!$oOption->paramTest('remove', 'y'))
                {
                    $strValue = $self->{oManifest}->variableReplace(trim($oOption->valueGet(false)));
                }

                if (!defined($strValue))
                {
                    delete(${$self->{config}}{$strHostName}{$strFile}{$strSection}{$strKey});

                    if (keys(%{${$self->{config}}{$strHostName}{$strFile}{$strSection}}) == 0)
                    {
                        delete(${$self->{config}}{$strHostName}{$strFile}{$strSection});
                    }

                    &log(DEBUG, ('    ' x ($iDepth + 1)) . "reset ${strSection}->${strKey}");
                }
                else
                {
                    # Get the config options hash
                    my $oOption = optionRuleGet();

                    # Make sure the specified option exists
                    if (!defined($$oOption{$strKey}))
                    {
                        confess &log(ERROR, "option ${strKey} does not exist");
                    }

                    # If this option is a hash and the value is already set then append to the array
                    if ($$oOption{$strKey}{&OPTION_RULE_TYPE} eq OPTION_TYPE_HASH &&
                        defined(${$self->{config}}{$strHostName}{$strFile}{$strSection}{$strKey}))
                    {
                        my @oValue = ();
                        my $strHashValue = ${$self->{config}}{$strHostName}{$strFile}{$strSection}{$strKey};

                        # If there is only one key/value
                        if (ref(\$strHashValue) eq 'SCALAR')
                        {
                            push(@oValue, $strHashValue);
                        }
                        # Else if there is an array of values
                        else
                        {
                            @oValue = @{$strHashValue};
                        }

                        push(@oValue, $strValue);
                        ${$self->{config}}{$strHostName}{$strFile}{$strSection}{$strKey} = \@oValue;
                    }
                    # else just set the value
                    else
                    {
                        ${$self->{config}}{$strHostName}{$strFile}{$strSection}{$strKey} = $strValue;
                    }

                    &log(DEBUG, ('    ' x ($iDepth + 1)) . "set ${strSection}->${strKey} = ${strValue}");
                }
            }

            my $strLocalFile = "/home/vagrant/data/db-master/etc/pgbackrest.conf";

            # Save the ini file
            iniSave($strLocalFile, $self->{config}{$strHostName}{$strFile}, true);

            $strConfig = fileStringRead($strLocalFile);

            $oHost->copyTo($strLocalFile, $strFile, $oConfig->paramGet('owner', false, 'postgres:postgres'), '640');
        }
        else
        {
            $strConfig = 'Config suppressed for testing';
        }

        $oConfig->fieldSet('actual-file', $strFile);
        $oConfig->fieldSet('actual-config', $strConfig);
        $self->cachePush($strCacheType, $hCacheKey, $hCacheValue);
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strFile', value => $strFile, trace => true},
        {name => 'strConfig', value => $strConfig, trace => true},
        {name => 'bShow', value => $oConfig->paramTest('show', 'n') ? false : true, trace => true}
    );
}

####################################################################################################################################
# postgresConfig
####################################################################################################################################
sub postgresConfig
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $oSection,
        $oConfig,
        $iDepth
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->postgresConfig', \@_,
            {name => 'oSection'},
            {name => 'oConfig'},
            {name => 'iDepth'}
        );

    # Working variables
    my $strFile;
    my $strConfig;

    my ($bCacheHit, $strCacheType, $hCacheKey, $hCacheValue) = $self->cachePop('cfg-postgresql', $self->configKey($oConfig));

    if ($oConfig->fieldTest('actual-file'))
    {
        $strFile = $oConfig->fieldGet('actual-file');
        $strConfig = $oConfig->fieldGet('actual-config');
    }
    else
    {
        # Get filename
        $strFile = $self->{oManifest}->variableReplace($oConfig->paramGet('file'));

        if ($self->{bExe} && $self->isRequired($oSection))
        {
            # Check that the host is valid
            my $strHostName = $self->{oManifest}->variableReplace($oConfig->paramGet('host'));
            my $oHost = $self->{host}{$strHostName};

            if (!defined($oHost))
            {
                confess &log(ERROR, "cannot configure postgres on host ${strHostName} because the host does not exist");
            }

            my $strLocalFile = '/home/vagrant/data/db-master/etc/postgresql.conf';
            $oHost->copyFrom($strFile, $strLocalFile);

            if (!defined(${$self->{'pg-config'}}{$strHostName}{$strFile}{base}) && $self->{bExe})
            {
                ${$self->{'pg-config'}}{$strHostName}{$strFile}{base} = fileStringRead($strLocalFile);
            }

            my $oConfigHash = $self->{'pg-config'}{$strHostName}{$strFile};
            my $oConfigHashNew;

            if (!defined($$oConfigHash{old}))
            {
                $oConfigHashNew = {};
                $$oConfigHash{old} = {}
            }
            else
            {
                $oConfigHashNew = dclone($$oConfigHash{old});
            }

            &log(DEBUG, ('    ' x $iDepth) . 'process postgres config: ' . $strFile);

            foreach my $oOption ($oConfig->nodeList('postgres-config-option'))
            {
                my $strKey = $oOption->paramGet('key');
                my $strValue = $self->{oManifest}->variableReplace(trim($oOption->valueGet()));

                if ($strValue eq '')
                {
                    delete($$oConfigHashNew{$strKey});

                    &log(DEBUG, ('    ' x ($iDepth + 1)) . "reset ${strKey}");
                }
                else
                {
                    $$oConfigHashNew{$strKey} = $strValue;
                    &log(DEBUG, ('    ' x ($iDepth + 1)) . "set ${strKey} = ${strValue}");
                }
            }

            # Generate config text
            foreach my $strKey (sort(keys(%$oConfigHashNew)))
            {
                if (defined($strConfig))
                {
                    $strConfig .= "\n";
                }

                $strConfig .= "${strKey} = $$oConfigHashNew{$strKey}";
            }

            # Save the conf file
            if ($self->{bExe})
            {
                fileStringWrite($strLocalFile, $$oConfigHash{base} .
                                (defined($strConfig) ? "\n# pgBackRest Configuration\n${strConfig}\n" : ''));

                $oHost->copyTo($strLocalFile, $strFile, 'postgres:postgres', '640');
            }

            $$oConfigHash{old} = $oConfigHashNew;
        }
        else
        {
            $strConfig = 'Config suppressed for testing';
        }

        $oConfig->fieldSet('actual-file', $strFile);
        $oConfig->fieldSet('actual-config', $strConfig);
        $self->cachePush($strCacheType, $hCacheKey, $hCacheValue);
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strFile', value => $strFile, trace => true},
        {name => 'strConfig', value => $strConfig, trace => true},
        {name => 'bShow', value => $oConfig->paramTest('show', 'n') ? false : true, trace => true}
    );
}

####################################################################################################################################
# hostKey
####################################################################################################################################
sub hostKey
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $oHost,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->hostKey', \@_,
            {name => 'oHost', trace => true},
        );

    my $hCacheKey =
    {
        name => $self->{oManifest}->variableReplace($oHost->paramGet('name')),
        user => $self->{oManifest}->variableReplace($oHost->paramGet('user')),
        image => $self->{oManifest}->variableReplace($oHost->paramGet('image')),
    };

    if (defined($oHost->paramGet('os', false)))
    {
        $$hCacheKey{os} = $self->{oManifest}->variableReplace($oHost->paramGet('os'));
    }

    if (defined($oHost->paramGet('mount', false)))
    {
        $$hCacheKey{mount} = $self->{oManifest}->variableReplace($oHost->paramGet('mount'));
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'hCacheKey', value => $hCacheKey, trace => true}
    );
}

####################################################################################################################################
# cachePop
####################################################################################################################################
sub cachePop
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strCacheType,
        $hCacheKey,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->hostKey', \@_,
            {name => 'strCacheType', trace => true},
            {name => 'hCacheKey', trace => true},
        );

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'bCacheHit', value => false, trace => true},
        {name => 'strCacheType', value => $strCacheType, trace => true},
        {name => 'hCacheKey', value => $hCacheKey, trace => true},
        {name => 'oCacheValue', value => undef, trace => true},
    );
}

####################################################################################################################################
# cachePush
####################################################################################################################################
sub cachePush
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strType,
        $hCacheKey,
        $oCacheValue,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->hostKey', \@_,
            {name => 'strType', trace => true},
            {name => 'hCacheKey', trace => true},
            {name => 'oCacheValue', required => false, trace => true},
        );

    # Create the cache entry
    my $hCache =
    {
        key => $hCacheKey,
        type => $strType,
    };

    if (defined($oCacheValue))
    {
        $$hCache{value} = $oCacheValue;
    }

    push @{$self->{oSource}{hyCache}}, $hCache;

    # Return from function and log return values if any
    return logDebugReturn($strOperation);
}

####################################################################################################################################
# sectionChildProcesss
####################################################################################################################################
sub sectionChildProcess
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $oSection,
        $oChild,
        $iDepth
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->sectionChildProcess', \@_,
            {name => 'oSection'},
            {name => 'oChild'},
            {name => 'iDepth'}
        );

    &log(DEBUG, ('    ' x ($iDepth + 1)) . 'process child: ' . $oChild->nameGet());

    # Execute a command
    if ($oChild->nameGet() eq 'host-add')
    {
        if ($self->{bExe} && $self->isRequired($oSection) && !$oChild->paramTest('created', true))
        {
            my ($bCacheHit, $strCacheType, $hCacheKey, $hCacheValue) = $self->cachePop('host', $self->hostKey($oChild));

            if (defined($self->{host}{$$hCacheKey{name}}))
            {
                confess &log(ERROR, 'cannot add host ${strName} because the host already exists');
            }

            my $oHost =
                new pgBackRestTest::Common::HostTest(
                    $$hCacheKey{name}, $$hCacheKey{image}, $$hCacheKey{user}, $$hCacheKey{os}, $$hCacheKey{mount});

            $self->{host}{$$hCacheKey{name}} = $oHost;
            $self->{oManifest}->variableSet("host-$$hCacheKey{name}-ip", $oHost->{strIP});
            $self->cachePush($strCacheType, $hCacheKey, $hCacheValue);

            # Execute cleanup commands
            foreach my $oExecute ($oChild->nodeList('execute'))
            {
                $self->execute($oSection, $$hCacheKey{name}, $oExecute, $iDepth + 1);
            }

            $oHost->executeSimple("sh -c 'echo \"\" >> /etc/hosts\'", undef, 'root');
            $oHost->executeSimple("sh -c 'echo \"# Test Hosts\" >> /etc/hosts'", undef, 'root');

            # Add all other host IPs to this host
            foreach my $strOtherHostName (sort(keys(%{$self->{host}})))
            {
                if ($strOtherHostName ne $$hCacheKey{name})
                {
                    my $oOtherHost = $self->{host}{$strOtherHostName};

                    $oHost->executeSimple("sh -c 'echo \"$oOtherHost->{strIP} ${strOtherHostName}\" >> /etc/hosts'", undef, 'root');
                }
            }

            # Add this host IP to all other hosts
            foreach my $strOtherHostName (sort(keys(%{$self->{host}})))
            {
                if ($strOtherHostName ne $$hCacheKey{name})
                {
                    my $oOtherHost = $self->{host}{$strOtherHostName};

                    $oOtherHost->executeSimple("sh -c 'echo \"$oHost->{strIP} $$hCacheKey{name}\" >> /etc/hosts'", undef, 'root');
                }
            }

            $oChild->paramSet('created', true);
        }
    }
    # Skip children that have already been processed and error on others
    elsif ($oChild->nameGet() ne 'title')
    {
        confess &log(ASSERT, 'unable to process child type ' . $oChild->nameGet());
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation
    );
}

1;

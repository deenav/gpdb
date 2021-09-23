@gpstart
Feature: gpstart behave tests

    @concourse_cluster
    @demo_cluster
    Scenario: gpstart correctly identifies down segments
        Given the database is running
          And a mirror has crashed
          And the database is not running
         When the user runs "gpstart -a"
         Then gpstart should return a return code of 0
          And gpstart should print "Skipping startup of segment marked down in configuration" to stdout
          And gpstart should print "Skipped segment starts \(segments are marked down in configuration\) += 1" to stdout
          And gpstart should print "Successfully started [0-9]+ of [0-9]+ segment instances, skipped 1 other segments" to stdout
          And gpstart should print "Number of segments not attempted to start: 1" to stdout

    Scenario: gpstart starts even if the standby host is unreachable
        Given the database is running
          And the catalog has a standby coordinator entry

         When the standby host is made unreachable
          And the user runs command "pkill -9 postgres"
          And "gpstart" is run with prompts accepted

         Then gpstart should print "Continue only if you are certain that the standby is not acting as the coordinator." to stdout
          And gpstart should print "No standby coordinator configured" to stdout
          And gpstart should return a return code of 0
          And all the segments are running

    @concourse_cluster
    @demo_cluster
    Scenario: gpstart starts even if a segment host is unreachable
        Given the database is running
          And the host for the primary on content 0 is made unreachable
          And the host for the mirror on content 1 is made unreachable

          And the user runs command "pkill -9 postgres" on all hosts without validation
         When "gpstart" is run with prompts accepted

         Then gpstart should print "Host invalid_host is unreachable" to stdout
          And gpstart should print unreachable host messages for the down segments
          And the status of the primary on content 0 should be "d"
          And the status of the mirror on content 1 should be "d"

          And the cluster is returned to a good state


############################

    @concourse_cluster
    @demo_cluster
    Scenario: "gpstart -a" accepts all (non-super user and utility mode) connections
        Given the database is running
          And the user runs psql with "-c 'create user foouser login;'" against database "postgres"
          And the user runs command "echo 'local all foouser trust' >> $COORDINATOR_DATA_DIRECTORY/pg_hba.conf"
          And the database is not running
          And the user runs "gpstart -a"
          And "gpstart -a" should return a return code of 0

         When The user runs psql "-c '\l'" in "postgres" in utility mode
         Then command should return a return code of 0

         When The user runs psql "-U foouser -c '\l'" in "postgres" in utility mode
         Then command should return a return code of 0

         When The user runs psql " -c '\l'" in "postgres"
         Then command should return a return code of 0

         When The user runs psql "-U foouser -c '\l'" in "postgres"
         Then command should return a return code of 0

#Examples:
#        | test description                                          | return_code | should_confirm | print_statement        | should_update_master | should_update_segment | cmd                                                                               |
#        | super user connections | 0           | should         | completed successfully | should               | should                | gpconfig -c application_name -v "easy" < test/behave/mgmt_utils/steps/data/yes.txt|
#        | non-super user connections   | 0           | should         | User Aborted. Exiting. | should not           | should not            | gpconfig -c application_name -v "easy" < test/behave/mgmt_utils/steps/data/no.txt |
#        | non-super user connections in Utility mode     | 0           | should not     | completed successfully | should               | should not            | gpconfig -c application_name -v "easy" --masteronly                               |
#        | super user connections in Utility mode     | 0           | should not     | completed successfully | should               | should not            | gpconfig -c application_name -v "easy" --masteronly                               |

# Examples:
#        | test description                               |  psql cmd  |return_code | should_confirm | print_statement        | should_update_coordinator | should_update_segment | cmd                                                                               |
#        | super user connections in Utility mode         | 0           | should         | completed successfully | should                    | should                | gpconfig -c application_name -v "easy" < test/behave/mgmt_utils/steps/data/yes.txt|
#        | non-super user connections in Utility mode     | 0           | should         | User Aborted. Exiting. | should not                | should not            | gpconfig -c application_name -v "easy" < test/behave/mgmt_utils/steps/data/no.txt |
#        | super user connections                         | 0           | should         | completed successfully | should                    | should                | gpconfig -c application_name -v "easy" < test/behave/mgmt_utils/steps/data/yes.txt|
#        | non-super user connections                     | 0           | should         | User Aborted. Exiting. | should not                | should not            | gpconfig -c application_name -v "easy" < test/behave/mgmt_utils/steps/data/no.txt |

    # NOTE: There are couple of open bugs existing for utility mode connections (gpstart -m & gpstart -mR) behavior on GP-7x
    # https://github.com/greenplum-db/gpdb/issues/12217 and https://github.com/greenplum-db/gpdb/issues/12566
    # Expected result of below test cases might change based on above issues fix
    @concourse_cluster
    @demo_cluster
    Scenario: "gpstart -m -a" should allow only utility mode connections
        Given the database is not running
          And the user runs "gpstart -ma"
          And "gpstart -m -a" should return a return code of 0

         When The user runs psql "-c '\l'" in "postgres" in utility mode
         Then command should return a return code of 0

         When The user runs psql "-U foouser -c '\l'" in "postgres" in utility mode
         Then command should return a return code of 0

        When The user runs psql "-c '\l'" in "postgres"
         Then command should return a return code of 0

         When The user runs psql "-U foouser -c '\l'" in "postgres"
         Then command should return a return code of 0

          And the user runs "gpstop -mai"
          And "gpstop -mai" should return a return code of 0


    @concourse_cluster
    @demo_cluster
    Scenario: "gpstart -m -R -a" should allow only super user in utility mode connections
        Given the database is not running
          And the user runs "gpstart -m -R -a"
          And gpstart should return a return code of 0

         When The user runs psql "-c '\l'" in "postgres" in utility mode
         Then command should return a return code of 0

         When The user runs psql "-U foouser -c '\l'" in "postgres" in utility mode
         Then command should return a return code of 2
          And command should print "psql: FATAL:  remaining connection slots are reserved for non-replication superuser connections" error message

         When The user runs psql "-c '\l'" in "postgres"
         Then command should return a return code of 0

         When The user runs psql "-U foouser -c '\l'" in "postgres"
         Then command should return a return code of 2
          And command should print "psql: FATAL:  remaining connection slots are reserved for non-replication superuser connections" error message

          And the user runs "gpstop -mai"
          And "gpstop -mai" should return a return code of 0


    @concourse_cluster
    @demo_cluster
    Scenario: "gpstart -R -a" should not allow non-super user connections
        Given the database is not running
          And the user runs "gpstart -R -a"
          And gpstart should return a return code of 0

         When The user runs psql "-c '\l'" in "postgres" in utility mode
         Then command should return a return code of 0

         When The user runs psql "-U foouser -c '-l'" in "postgres" in utility mode
         Then command should return a return code of 2
          And command should print "psql: FATAL:  remaining connection slots are reserved for non-replication superuser connections" error message

         When The user runs psql "-c '\l'" in "postgres"
         Then command should return a return code of 0

         When The user runs psql "-U foouser -c '-l'" in "postgres"
         Then command should return a return code of 2
          And command should print "psql: FATAL:  remaining connection slots are reserved for non-replication superuser connections" error message

          And The user runs psql with "-c 'drop user foouser;'" against database "postgres"
          And the user runs "gpstop -ai"
          And "gpstop -ai" should return a return code of 0
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

    # Start the database with "gpstart" and test all psql login scenarios below
    # | test scenarios                                 | psql cmd                                                           | return_code | DB login      | error message |
    # | super user connections in Utility mode         | PGOPTIONS="-c gp_role=utility" psql -d postgres -c '/l'            | 0           | success       | None          |
    # | non-super user connections in Utility mode     | PGOPTIONS="-c gp_role=utility" psql -d postgres -u foouser -c '/l' | 0           | success       | None          |
    # | super user connections                         | psql -d postgres -c '\l'                                           | 0           | success       | None          |
    # | non-super user connections                     | psql -d postgres -u foouser -c '/l'                                | 0           | success       | None          |

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


    # Start the database with "gpstart -m" and test all psql login scenarios below
    # | test scenarios                                 | psql cmd                                                           | return_code | DB login      | error message |
    # | super user connections in Utility mode         | PGOPTIONS="-c gp_role=utility" psql -d postgres -c '/l'            | 0           | success       | None          |
    # | non-super user connections in Utility mode     | PGOPTIONS="-c gp_role=utility" psql -d postgres -u foouser -c '/l' | 0           | success       | None          |
    # | super user connections                         | psql -d postgres -c '\l'                                           | 0           | success       | None          |
    # | non-super user connections                     | psql -d postgres -u foouser -c '/l'                                | 0           | success       | None          |

    # NOTE: On GP-7x, There are couple of open bugs existing for utility mode connections (gpstart -m & gpstart -mR)
    # https://github.com/greenplum-db/gpdb/issues/12217 : "gpstart -m" accepts connections without checking "gp_role=utility"
    # https://github.com/greenplum-db/gpdb/issues/12566 :  Non-superuser should not be able to connect via utility mode

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

    # Start the database with "gpstart -m -R" and test all psql login scenarios below
    # | test scenarios                                 | psql cmd                                                           | return_code | DB login      | error message |
    # | super user connections in Utility mode         | PGOPTIONS="-c gp_role=utility" psql -d postgres -c '/l'            | 0           | success       | None          |
    # | non-super user connections in Utility mode     | PGOPTIONS="-c gp_role=utility" psql -d postgres -u foouser -c '/l' | 2           | failure       | psql: error: FATAL:  remaining connection slots are reserved for non-replication superuser connections          |
    # | super user connections                         | psql -d postgres -c '\l'                                           | 0           | success       | None          |
    # | non-super user connections                     | psql -d postgres -u foouser -c '/l'                                | 2           | failure       | psql: error: FATAL:  remaining connection slots are reserved for non-replication superuser connections         |

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
          And command should print "psql: error: FATAL:  remaining connection slots are reserved for non-replication superuser connections" error message

         When The user runs psql "-c '\l'" in "postgres"
         Then command should return a return code of 0

         When The user runs psql "-U foouser -c '\l'" in "postgres"
         Then command should return a return code of 2
          And command should print "psql: error: FATAL:  remaining connection slots are reserved for non-replication superuser connections" error message

          And the user runs "gpstop -mai"
          And "gpstop -mai" should return a return code of 0

    # Start the database with "gpstart -R" and test all psql login scenarios below
    # | test scenarios                                 | psql cmd                                                           | return_code | DB login      | error message |
    # | super user connections in Utility mode         | PGOPTIONS="-c gp_role=utility" psql -d postgres -c '/l'            | 0           | success       | None          |
    # | non-super user connections in Utility mode     | PGOPTIONS="-c gp_role=utility" psql -d postgres -u foouser -c '/l' | 2           | failure       | psql: error: FATAL:  remaining connection slots are reserved for non-replication superuser connections          |
    # | super user connections                         | psql -d postgres -c '\l'                                           | 0           | success       | None          |
    # | non-super user connections                     | psql -d postgres -u foouser -c '/l'                                | 2           | failure       | psql: error: FATAL:  remaining connection slots are reserved for non-replication superuser connections         |

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
          And command should print "psql: error: FATAL:  remaining connection slots are reserved for non-replication superuser connections" error message

         When The user runs psql "-c '\l'" in "postgres"
         Then command should return a return code of 0

         When The user runs psql "-U foouser -c '-l'" in "postgres"
         Then command should return a return code of 2
          And command should print "psql: error: FATAL:  remaining connection slots are reserved for non-replication superuser connections" error message

          And The user runs psql with "-c 'drop user foouser;'" against database "postgres"
          And the user runs "gpstop -ai"
          And "gpstop -ai" should return a return code of 0


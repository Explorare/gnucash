set(account_DATA
 acctchrt_actifsfixes.gnucash-xea
 acctchrt_automobile.gnucash-xea
 acctchrt_basecommune.gnucash-xea
 acctchrt_cdmarchemon.gnucash-xea
 acctchrt_chequier.gnucash-xea
 acctchrt_conjointretraite.gnucash-xea
 acctchrt_conjointrev.gnucash-xea
 acctchrt_courtage.gnucash-xea
 acctchrt_etudeemprunt.gnucash-xea
 acctchrt_garderie.gnucash-xea
 acctchrt_locataire.gnucash-xea
 acctchrt_proprietaire.gnucash-xea
 acctchrt_retraite.gnucash-xea
 acctchrt_revenus.gnucash-xea)

set_dist_list(FR_CA_DIST ${account_DATA} CMakeLists.txt)

install(FILES ${account_DATA} DESTINATION ${ACCOUNTS_INSTALL_DIR}/fr_CA)

foreach(acct_file ${account_DATA})
    configure_file(${acct_file} ${ACCOUNTS_BUILD_DIR}/fr_CA/${acct_file} COPYONLY)
endforeach()

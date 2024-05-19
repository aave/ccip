CMN="--typecheck_only"



echo "******** Running:  1 ***************"
certoraRun $CMN certora/conf/AToken.conf \
           --msg "1: AToken.conf"

echo "******** Running:  2 ***************"
certoraRun $CMN certora/conf/Pool.conf \
           --msg "2: Pool.conf"

echo "******** Running:  3 ***************"
certoraRun $CMN certora/conf/ReserveConfiguration.conf \
           --msg "3: ReserveConfiguration.conf"

echo "******** Running:  4 ***************"
certoraRun $CMN certora/conf/StableTokenCLI.conf \
           --msg "4: StableTokenCLI.conf"

echo "******** Running:  5 ***************"
certoraRun $CMN certora/conf/UserConfigCLI.conf \
           --msg "5: UserConfigCLI.conf"

echo "******** Running:  6 ***************"
certoraRun $CMN certora/conf/VariableTokenCLI.conf \
           --msg "6: VariableTokenCLI.conf"

echo "******** Running:  7 NEW no summarization ***************"
certoraRun $CMN certora/conf/NEW-pool-no-summarizations.conf
           --msg "7: NEW-pool-no-summarizations"


echo "******** Running:  simple:1 ***************"
certoraRun $CMN certora/conf/NEW-pool-simple-properties.conf \
           --rule cannotDepositInInactiveReserve \
           --msg "simple:1: NEW :: cannotDepositInInactiveReserve"

echo "******** Running:  simple:2 ***************"
certoraRun $CMN certora/conf/NEW-pool-simple-properties.conf \
           --rule cannotDepositInFrozenReserve \
           --msg "simple:2: NEW :: cannotDepositInFrozenReserve"

echo "******** Running:  simple:3 ***************"
certoraRun $CMN certora/conf/NEW-pool-simple-properties.conf \
           --rule cannotDepositZeroAmount \
           --msg "simple:3: NEW :: cannotDepositZeroAmount"

echo "******** Running:  simple:4 ***************"
certoraRun $CMN certora/conf/NEW-pool-simple-properties.conf \
           --rule cannotWithdrawZeroAmount \
           --msg "simple:4: NEW :: cannotWithdrawZeroAmount"

echo "******** Running:  simple:5 ***************"
certoraRun $CMN certora/conf/NEW-pool-simple-properties.conf \
           --rule cannotWithdrawFromInactiveReserve \
           --msg "simple:5: NEW :: cannotWithdrawFromInactiveReserve"

echo "******** Running:  simple:6 ***************"
certoraRun $CMN certora/conf/NEW-pool-simple-properties.conf \
           --rule cannotBorrowZeroAmount \
           --msg "simple:6: NEW :: cannotBorrowZeroAmount"

echo "******** Running:  simple:7 ***************"
certoraRun $CMN certora/conf/NEW-pool-simple-properties.conf \
           --rule cannotBorrowOnInactiveReserve \
           --msg "simple:7: NEW :: cannotBorrowOnInactiveReserve"

echo "******** Running:  simple:8 ***************"
certoraRun $CMN certora/conf/NEW-pool-simple-properties.conf \
           --rule cannotBorrowOnReserveDisabledForBorrowing \
           --msg "simple:8: NEW :: cannotBorrowOnReserveDisabledForBorrowing"

echo "******** Running:  simple:9 ***************"
certoraRun $CMN certora/conf/NEW-pool-simple-properties.conf \
           --rule cannotBorrowOnFrozenReserve \
           --msg "simple:9: NEW :: cannotBorrowOnFrozenReserve"



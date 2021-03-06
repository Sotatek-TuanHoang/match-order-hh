pragma solidity ^0.6.5;
pragma experimental ABIEncoderV2;
import "hardhat/console.sol";

interface OwnableFeatureInterface {
    /// @dev Emitted when `migrate()` is called.
    /// @param caller The caller of `migrate()`.
    /// @param migrator The migration contract.
    /// @param newOwner The address of the new owner.
    event Migrated(address caller, address migrator, address newOwner);

    /// @dev Execute a migration function in the context of the ZeroEx contract.
    ///      The result of the function being called should be the magic bytes
    ///      0x2c64c5ef (`keccack('MIGRATE_SUCCESS')`). Only callable by the owner.
    ///      The owner will be temporarily set to `address(this)` inside the call.
    ///      Before returning, the owner will be set to `newOwner`.
    /// @param target The migrator contract address.
    /// @param newOwner The address of the new owner.
    /// @param data The call data.
    function migrate(address target, bytes calldata data, address newOwner) external;
    function transferOwnership(address newOwner) external;
}

interface FeatureInterface {
    function migrate() external returns (bytes4 success);
}

contract AddFeature {

    // constructor(
    //     address zeroExAddress,
    //     address featureAddress,
    //     address ownableFeatureAddress
    // )
    // public {
    //     addNewFeature(zeroExAddress, featureAddress, ownableFeatureAddress);
    // }
    function die(address payable ethRecipient)
        public
        virtual
    {
        require(msg.sender == address(this), "FullMigration/INVALID_SENDER");
        // This contract should not hold any funds but we send
        // them to the ethRecipient just in case.
        selfdestruct(ethRecipient);
    }

    function addNewFeature(
        address zeroExAddress,
        address featureAddress,
        address ownableFeatureAddress
    )
    external
    returns (bool rs) {

        OwnableFeatureInterface ownableFeature = OwnableFeatureInterface(ownableFeatureAddress);
        FeatureInterface feature = FeatureInterface(featureAddress);
        ownableFeature.migrate(
            featureAddress, 
            abi.encodeWithSelector(feature.migrate.selector),
            address(this)
        );
        ownableFeature.transferOwnership(msg.sender);
        die(msg.sender);
        return true;
    }

}
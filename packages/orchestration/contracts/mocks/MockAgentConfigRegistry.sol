// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAgentConfigRegistry} from "../interfaces/core/IAgentConfigRegistry.sol";

contract MockAgentConfigRegistry is IAgentConfigRegistry {
    mapping(address => AgentConfig) private _configs;
    mapping(address => bool) private _registered;

    function setAgentConfig(address agent, AgentConfig calldata config) external {
        _configs[agent] = config;
        _registered[agent] = true;
    }

    function getAgentConfig(address agent) external view returns (AgentConfig memory config) {
        config = _configs[agent];
    }

    function isRegisteredAgent(address agent) external view returns (bool) {
        return _registered[agent];
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Multicall {
    struct Call {
        address target;
        bytes callData;
        uint256 value;
    }

    struct Result {
        bool success;
        bytes data;
    }

    function multicall(Call[] calldata calls) public payable returns (Result[] memory results) {
        results = new Result[](calls.length);
        uint256 totalValue = 0;

        for (uint256 i = 0; i < calls.length; i++) {
            totalValue += calls[i].value;
            require(totalValue <= msg.value, "Insufficient value provided");

            (bool success, bytes memory result) = (false, "");
            if (calls[i].value > 0) {
                (success, result) = calls[i].target.call{value: calls[i].value}(calls[i].callData);
            } else {
                (success, result) = calls[i].target.call(calls[i].callData);
            }
            require(success, "Multicall aggregate: call failed");
            results[i] = Result(success, result);
        }
    }

    function aggregate(Call[] memory calls) public payable returns (bool[] memory, bytes[] memory) {
        bool[] memory success = new bool[](calls.length);
        bytes[] memory results = new bytes[](calls.length);

        uint256 totalValueSent = 0;

        for (uint256 i = 0; i < calls.length; i++) {
            // 确保转账金额不会超过合约中存入的主币总量
            require(totalValueSent + calls[i].value <= msg.value, "Insufficient value sent");

            // 提取 callData 的前 4 个字节（函数选择器）
            bytes4 selector;
            bytes memory data = calls[i].callData;
            assembly {
                selector := mload(add(data, 32))  // 提取前 4 个字节作为函数选择器
            }

            // 手动跳过前 4 个字节进行解码
            (/*address originalCaller*/, uint256 value, bool flag) = decodeCallData(data);

            // 强制修改第一个参数为 msg.sender
            address newCaller = msg.sender;

            // 使用修改后的参数重新编码 callData
            bytes memory modifiedCallData = abi.encodeWithSelector(
                selector,                   // 使用函数选择器
                newCaller,                  // 替换第一个参数为新的调用者
                value,                      // 保留原始的 value 参数
                flag                        // 保留原始的 flag 参数
            );

            // 累计主币的转账金额
            totalValueSent += calls[i].value;

            // 使用 call{value: calls[i].value} 调用目标合约
            (success[i], results[i]) = calls[i].target.call{value: calls[i].value}(modifiedCallData);
        }

//        emit MulticallExecuted(msg.sender, success, results);
        return (success, results);
    }

    // 辅助函数，手动跳过前 4 个字节解码参数
    function decodeCallData(bytes memory data) internal pure returns (address, uint256, bool) {
        address originalCaller;
        uint256 value;
        bool flag;

        // 使用 assembly 手动跳过前 4 个字节
        assembly {
            originalCaller := mload(add(data, 36))  // 跳过前 4 个字节（函数选择器），再跳过 32 字节的内存偏移量
            value := mload(add(data, 68))           // 第二个参数
            flag := mload(add(data, 100))           // 第三个参数
        }

        return (originalCaller, value, flag);
    }

}
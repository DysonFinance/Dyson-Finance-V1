# Dyson Finance
## Foundry
### Useful Commands
```shell
forge build
forge test
forge test -vv
forge test -vvvv
forge test --contracts ./src/test/Contract.t.sol
```

### Test Template
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "ds-test/test.sol";
import 'src/XX.sol';
import './console.sol';
import './Vm.sol';


contract XXTest is DSTest {
    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    address public owner;
    mapping(uint => address) public addrs;

    XX xx;

    // The state of the contract gets reset before each
    // test is run, with the `setUp()` function being called
    // each time after deployment.
    function setUp() public {
        owner = address(this);
        for (uint i = 1; i <= 10; i++) {
            addrs[i] = vm.addr(i);
        }
    }

    function testExample() public {
        assertTrue(true);
    }
}

```
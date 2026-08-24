# Pack 协同开战设计

当已登记 Pack 中任一存活 EnemyBase 从非战斗进入战斗，EncounterController 读取其有效锁定目标，并将该目标作为运行时协同目标广播给同 Pack 的其余存活成员。协同目标优先于各自的范围索敌，允许尚未进入个人感知半径的敌人立即加入攻击。

协同目标只保存在 AITargetingComponent 的运行时覆盖字段中，仍验证目标存活、可选取、在场景树内且与敌人敌对；不写入仇恨表。Pack 完成现有 reset 倒计时或被清除时，EncounterController 统一撤销覆盖。

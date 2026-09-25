from __future__ import annotations

import unittest

try:
    import torch  # noqa: F401
    HAS_TORCH = True
except ImportError:
    HAS_TORCH = False

if HAS_TORCH:
    from pig_farm_agent.model_runtime.soft_nms import ACTION_NAMES, box_iou_torch, deterministic_order


@unittest.skipUnless(HAS_TORCH, "本机未安装 torch，跳过 Soft-NMS 单元测试")
class TestSoftNms(unittest.TestCase):
    def test_box_iou_identity_and_disjoint(self):
        a = torch.tensor([[0.0, 0.0, 10.0, 10.0]])
        iou = box_iou_torch(a, a)
        self.assertAlmostEqual(float(iou[0, 0]), 1.0, places=5)
        b = torch.tensor([[20.0, 20.0, 30.0, 30.0]])
        iou_ab = box_iou_torch(a, b)
        self.assertAlmostEqual(float(iou_ab[0, 0]), 0.0, places=6)

    def test_action_index_complete(self):
        self.assertEqual(
            set(ACTION_NAMES), {"keep", "refine", "rescore", "protect", "suppress"}
        )

    def test_deterministic_order_sorted_desc(self):
        scores = torch.tensor([0.3, 0.9, 0.5])
        order = deterministic_order(scores)
        self.assertEqual(order[0], 1)


if __name__ == "__main__":
    unittest.main()

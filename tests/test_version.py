import unittest
from app import app


class TestVersionRoute(unittest.TestCase):
    def test_version_route(self):
        response = app.test_client().get('/version')
        self.assertEqual(response.status_code, 200)
        self.assertIn('version', response.get_json())


if __name__ == '__main__':
    unittest.main()

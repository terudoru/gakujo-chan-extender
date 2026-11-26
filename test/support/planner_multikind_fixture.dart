const plannerMultiFetchPayload = {
  'v': 1,
  'packets': {
    // Deliberately out of order to verify canonical profile/grades/balances/registration order.
    'registration': {
      'v': 1,
      'kind': 'registration',
      'tables': [
        {
          'heading': '履修登録・登録状況照会',
          'rows': [
            ['開講番号', '登録状況'],
            ['269G9001', '申請中'],
            ['269G9002', '許可'],
          ],
        },
      ],
      'year': '2026',
    },
    'balances': {
      'v': 1,
      'kind': 'balances',
      'tables': [
        {
          'heading': '履修科目確認表',
          'rows': [
            ['科目区分', '既修得単位数'],
            ['教養教育に関する科目', '10.5'],
          ],
        },
      ],
    },
    'grades': {
      'v': 1,
      'kind': 'grades',
      'tables': [
        {
          'heading': '単位修得状況照会',
          'rows': [
            ['開講番号', '科目名', '単位数', '評価', '年度'],
            ['269G9001', '合成力学', '2', '優', '2026'],
          ],
        },
      ],
    },
    'profile': {
      'v': 1,
      'kind': 'profile',
      'tables': [
        {
          'heading': '学生所属',
          'rows': [
            ['所属', '学年'],
            ['理学部物理学科', '2'],
          ],
        },
      ],
    },
  },
};

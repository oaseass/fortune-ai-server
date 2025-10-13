from lunar_python import Solar

def build_saju_meta(y:int, m:int, d:int, H:int, M:int):
    solar = Solar(y, m, d, H, M, 0)
    lunar = solar.getLunar()
    ec = lunar.getEightChar()
    meta = {
        'year': ec.getYear(),
        'month': ec.getMonth(),
        'day': ec.getDay(),
        'time': ec.getTime(),
        'year_wuxing': ec.getYearWuXing(),
        'month_wuxing': ec.getMonthWuXing(),
        'day_wuxing': ec.getDayWuXing(),
        'time_wuxing': ec.getTimeWuXing(),
        'year_tiangan_shishen': ec.getYearShiShenGan(),
        'month_tiangan_shishen': ec.getMonthShiShenGan(),
        'day_tiangan_shishen': ec.getDayShiShenGan(),
        'time_tiangan_shishen': ec.getTimeShiShenGan(),
        'year_dizhi_shishen': list(ec.getYearShiShenZhi() or []),
        'month_dizhi_shishen': list(ec.getMonthShiShenZhi() or []),
        'day_dizhi_shishen': list(ec.getDayShiShenZhi() or []),
        'time_dizhi_shishen': list(ec.getTimeShiShenZhi() or []),
        'jieqi_table': {k: str(v.toYmdHms()) for k,v in (lunar.getJieQiTable() or {}).items()}
    }
    meta['year_ganji'] = meta['year']
    meta['month_ganji'] = meta['month']
    meta['day_ganji']  = meta['day']
    meta['hour_ganji'] = meta['time']
    meta['day_master'] = meta['day'][0]
    return meta


import sys
import time
import xlrd


def nFacilities(cl_data, ground_truth, n):
    wb = xlrd.open_workbook(ground_truth)
    sheet = wb.sheet_by_index(0)
    num_facilities = sheet.nrows

    with open('output.csv', 'w', newline='') as csvfile:
        filewriter = csv.writer(csvfile, delimiter=',', quotechar='|', quoting=csv.QUOTE_MINIMAL)
        filewriter.writerow(['Truth index', 'Parcel APN', 'Parcel lat', 'Parcel lon', 'Difference', 'Land Use'])

        with open(cl_data, 'r', encoding="utf8") as f:
            parcels = f.readlines()

            for k in range(len(parcels)):
                if k == 0:
                    continue
                tokens = parcels[k].split('|')
                par_zip = tokens[43][:5]
                subDict = {k: parcels[k]}
                if myDict.get(par_zip):
                    myDict[par_zip][k] = subDict[k]
                else:
                    myDict[par_zip] = subDict

            for i in range(num_facilities):
                try:
                    fac_zip = str(int(sheet.cell_value(i, 24)))
                    fac_lat = sheet.cell_value(i, 14)
                    fac_lon = sheet.cell_value(i, 15)
                    fac_index = sheet.cell_value(i, 0)
                except ValueError:
                    continue
                cur_closest = (0, 100)

                if myDict.get(fac_zip):
                    for candidate in myDict[fac_zip].keys():
                        cur = myDict[fac_zip][candidate]
                        info = cur.split('|')
                        try:
                            par_lat = float(info[30])
                            par_lon = float(info[31])
                        except ValueError:
                            continue
                        difference = (par_lat - fac_lat) ** 2 + (par_lon - fac_lon) ** 2
                        if difference < cur_closest[1]:
                            cur_closest = (cur, difference)

                if cur_closest[0] == 0:
                    filewriter.writerow([i, "No facility in this zip code."])
                else:
                    info = cur_closest[0].split('|')
                    filewriter.writerow([int(fac_index), info[1], info[30], info[31], cur_closest[1], info[18]])


def mMiles(cl_data, ground_truth, m):
    SELECT * FROM(
        SELECT *, (((acos(sin((@ latitude * pi() / 180)) * sin((Latitude * pi() / 180)) + cos(
            (@ latitude * pi() / 180)) * cos((Latitude * pi() / 180)) * cos(
            ((@ longitude - Longitude) * pi() / 180)))) * 180 / pi()) * 60 * 1.1515 * 1.609344) as distance FROM Distances) t
    WHERE distance <= @distance
    pass


def main():
    start_time = time.time()
    cl_data = sys.argv[2]
    ground_truth = sys.argv[3]
    if sys.argv[1] == 'n':
        nFacilities(cl_data, ground_truth, sys.argv[4])
    elif sys.argv[1] == 'm':
        mMiles(cl_data, ground_truth, sys.argv[4])
    else:
        print('More arguments needed.')
    print("--- %s seconds ---" % (time.time() - start_time))


if __name__ == '__main__':
    main()
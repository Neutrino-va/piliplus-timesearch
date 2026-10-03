import 'package:PiliPlus/models/dynamics/up.dart';
import 'package:PiliPlus/models/model_avatar.dart';

class FollowItemModel extends UpItem {
  int? attribute;
  String? sign;
  BaseOfficialVerify? officialVerify;

  /// 关注时间(unix 秒),接口 /x/relation/followings 每条自带
  int? mtime;

  FollowItemModel({
    required super.mid,
    this.attribute,
    super.uname,
    super.face,
    this.sign,
    this.officialVerify,
    this.mtime,
  });

  factory FollowItemModel.fromJson(Map<String, dynamic> json) =>
      FollowItemModel(
        mid: json['mid'] as int? ?? 0,
        attribute: json['attribute'] as int?,
        uname: json['uname'] as String?,
        face: json['face'] as String?,
        sign: json['sign'] as String?,
        officialVerify: json['official_verify'] == null
            ? null
            : BaseOfficialVerify.fromJson(
                json['official_verify'] as Map<String, dynamic>,
              ),
        mtime: json['mtime'] as int?,
      );
}

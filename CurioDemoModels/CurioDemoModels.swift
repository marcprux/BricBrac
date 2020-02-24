//
//  CurioDemoModels.swift
//  CurioDemoModels
//
//  Created by Marc Prud'hommeaux on 6/10/18.
//  Copyright © 2010-2020 io.glimpse. All rights reserved.
//


public class CurioDemoModels {
    public static var schemasFolder: String? {
        return Bundle(for: CurioDemoModels.self).path(forResource: "schemas", ofType: "")
    }
}
